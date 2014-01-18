%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  This module handles generic part of FSM attributes.
%%  FSM attribute is a mechanism for extending FSM at system level.
%%  Several extensions are provided within `eproc_core`, but other
%%  implementations can also be provided by an user.
%%
%%  TODO:
%%  API for the eproc_fsm.
%%  API for an attribute manager (for attaching attrs to FSM).
%%  SPI for the attribute manager (for handling attached attrs).
%%
%%  Differentiate between:
%%    * Attributes.
%%    * Attribute actions.
%%
%%  TODO: Define this while implementing `eproc_timer` module!!!
%%
-module(eproc_fsm_attr).
-compile([{parse_transform, lager_transform}]).
-export([action/4, action/3, make_event/2]).
-export([init/3, transition_start/4, transition_end/4, event/2]).
-include("eproc.hrl").


-record(attr_ctx, {
    attr_id :: integer(),
    attr    :: #attribute{},
    state   :: term()
}).
-record(state, {
    last_id :: integer(),
    attrs   :: [#attr_ctx{}]
}).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  FSM started.
%%
-callback init(
        ActiveAttrs :: [#attribute{}]
    ) ->
        {ok, [{Attribute :: #attribute{}, Data :: term()}]} |
        {error, Reason :: term()}.

%%
%%  Attribute created.
%%
-callback created(
        Name    :: term(),
        Action  :: term(),
        Scope   :: term()
    ) ->
        {create, Data, State} |
        {error, Reason}
    when
        Data :: term(),
        State :: term(),
        Reason :: term().

%%
%%  Attribute updated by user.
%%
-callback updated(
        Attribute   :: #attribute{},
        AttrState   :: term(),
        Action      :: term(),
        Scope       :: term() | undefined
    ) ->
        {update, NewData, NewState} |
        {remove, Reason} |
        {error, Reason}
    when
        NewData :: term(),
        NewState :: term(),
        Reason :: term().

%%
%%  Attribute removed by `eproc_fsm`.
%%
-callback removed(
        Attribute :: #attribute{},
        AttrState :: term()
    ) ->
        ok |
        {error, Reason :: term()}.



%% =============================================================================
%%  Functions for `eproc_fsm_attr` callback implementations.
%% =============================================================================


%%
%%  Registers new user action.
%%
action(Module, Name, Action, Scope) ->
    Actions = erlang:get('eproc_fsm_attr$actions'),
    erlang:put('eproc_fsm_attr$actions', [{Module, Name, Action, Scope} | Actions]),
    ok.


%%
%%  Registers new user action.
%%
action(Module, Name, Action) ->
    action(Module, Name, Action, undefined).


%%
%%
%%
make_event(#attribute{module = Module}, Event) ->
    Sender = {attr, Module},
    eproc_fsm:make_info(Sender, Event).     %% TODO: Implement.



%% =============================================================================
%%  Functions for `eproc_fsm`.
%% =============================================================================

%%
%%  Invoked, when the corresponding FSM is started (become online).
%%
init(_SName, LastId, ActiveAttrs) ->
    State = #state{
        last_id = LastId,
        attrs = init_on_start(ActiveAttrs, [])
    },
    {ok, State}.


%%
%%  Invoked at the start of each transition.
%%
transition_start(_InstId, _TrnNr, _SName, State) ->
    erlang:put('eproc_fsm_attr$actions', []),
    {ok, State}.


%%
%%  Invoked at the end of each transition.
%%
transition_end(InstId, TrnNr, NextSName, State = #state{last_id = LastAttrId, attrs = AttrCtxs}) ->
    ActionSpecs = erlang:erase('eproc_fsm_attr$actions'),
    {AttrCtxsAfterActions, UserActions, _, NewAttrId} = lists:foldl(
        fun perform_action/2,
        {AttrCtxs, [], {InstId, TrnNr, NextSName}, LastAttrId},
        ActionSpecs
    ),
    {NextSName, AttrCtxsAfterCleanup, CleanupActions} = lists:foldl(
        fun perform_cleanup/2,
        {NextSName, [], []},
        AttrCtxsAfterActions
    ),
    AllActions = UserActions ++ CleanupActions,
    NewState = State#state{
        last_id = NewAttrId,
        attrs = AttrCtxsAfterCleanup
    },
    {ok, AllActions, NewState}.


%%
%%  Invoked, when the FSM receives
%%
event({'eproc_fsm_attr$event', AttrId, Event}, State) ->
    % TODO: Handle.
    {ok, State};

event(_Event, _State) ->
    unknown.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%
%%
init_on_start([], Started) ->
    Started;

init_on_start(ActiveAttrs = [#attribute{module = Module} | _], Started) ->
    {Similar, Other} = lists:partition(fun (#attribute{module = M}) -> M =:= Module end, ActiveAttrs),
    case Module:init(Similar) of
        {ok, SimilarStarted} ->
            ConvertFun = fun ({A = #attribute{attr_id = AID}, S}) ->
                #attr_ctx{attr_id = AID, attr = A, state = S}
            end,
            init_on_start(Other, lists:map(ConvertFun, SimilarStarted) ++ Started);
        {error, Reason} ->
            erlang:throw({attr_init_failed, Reason})
    end.


%%
%%  Perform user actions on attributes.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_action(ActionSpec, {AttrCtxs, Actions, Context, LastAttrId}) ->
    {Module, Name, Action, Scope} = ActionSpec,
    case Name of
        undefined ->
            {ok, NewAttrCtx, NewAction, NewAttrId} = perform_create(Module, Name, Action, Scope, Context, LastAttrId),
            {[NewAttrCtx | AttrCtxs], [NewAction | Actions], Context, NewAttrId};
        _ ->
            ByNameFun = fun (#attr_ctx{attr = #attribute{name = N}}) -> N =:= Name end,
            case lists:partition(ByNameFun, AttrCtxs) of
                {[], AttrCtxs} ->
                    {ok, NewAttrCtx, NewAction, NewAttrId} = perform_create(Module, Name, Action, Scope, Context, LastAttrId),
                    {[NewAttrCtx | AttrCtxs], [NewAction | Actions], Context, NewAttrId};
                {[AttrCtx], OtherAttrCtxs} ->
                    case perform_update(AttrCtx, Action, Scope, Context) of
                        {updated, NewAttrCtx, NewAction} ->
                            {[NewAttrCtx | OtherAttrCtxs], [NewAction | Actions], Context, LastAttrId};
                        {removed, NewAction} ->
                            {OtherAttrCtxs, [NewAction | Actions], Context, LastAttrId}
                    end
            end
    end.


%%
%%  Create new attribute.
%%
perform_create(Module, Name, Action, Scope, {InstId, TrnNr, NextSName}, LastAttrId) ->
    ResolvedScope = resolve_scope(Scope, undefined, NextSName),
    case Module:created(Name, Action, ResolvedScope) of
        {create, AttrData, AttrState} ->
            NewAttrId = LastAttrId + 1,
            Attribute = #attribute{
                inst_id = InstId,
                attr_id = NewAttrId,
                module = Module,
                name = Name,
                scope = ResolvedScope,
                data = AttrData,
                from = TrnNr,
                upds = [],
                till = undefined
            },
            AttrCtx = #attr_ctx{
                attr_id = NewAttrId,
                attr = Attribute,
                state = AttrState
            },
            AttrAction = #attr_action{
                module = Module,
                attr_id = NewAttrId,
                action = {create, Name, ResolvedScope, AttrData}
            },
            {ok, AttrCtx, AttrAction, NewAttrId};
        {error, Reason} ->
            erlang:throw({attr_create_failed, Reason})
    end.


%%
%%  Update existing attribute.
%%
perform_update(AttrCtx, Action, Scope, {InstId, TrnNr, NextSName}) ->
    #attr_ctx{
        attr = Attribute,
        state = AttrState
    } = AttrCtx,
    #attribute{
        attr_id = AttrId,
        module = Module,
        scope = OldScope
    } = Attribute,
    ResolvedScope = resolve_scope(Scope, OldScope, NextSName),
    case Module:updated(Attribute, AttrState, Action, Scope) of
        {update, NewData, NewState} ->
            AttrAction = #attr_action{
                module = Module,
                attr_id = AttrId,
                action = {update, ResolvedScope, NewData}
            },
            NewAttribute = Attribute#attribute{
                data = NewData,
                scope = ResolvedScope
            },
            NewAttrCtx = AttrCtx#attr_ctx{
                attr = NewAttribute,
                state = NewState
            },
            {updated, NewAttrCtx, AttrAction};
        {remove, UserReason} ->
            AttrAction = #attr_action{
                module = Module,
                attr_id = AttrId,
                action = {remove, {user, UserReason}}
            },
            {removed, AttrAction};
        {error, Reason} ->
            erlang:throw({attr_update_failed, Reason})
    end.


%%
%%  Cleanup attributes, that became out-of-scope.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_cleanup(AttrCtx, {SName, AttrCtxs, Actions}) ->
    #attr_ctx{attr = Attr, state = State} = AttrCtx,
    #attribute{attr_id = AttrId, module = Module, scope = Scope} = Attr,
    case eproc_fsm:state_in_scope(SName, Scope) of
        true ->
            {SName, [AttrCtx | AttrCtxs], Actions};
        false ->
            case Module:removed(Attr, State) of
                ok ->
                    Action = #attr_action{
                        module = Module,
                        attr_id = AttrId,
                        action = {remove, {scope, SName}}
                    },
                    {SName, AttrCtxs, [Action | Actions]};
                {error, Reason} ->
                    erlang:throw({attr_cleanup_failed, Reason})
            end
    end.


%%
%%
%%
resolve_scope(Scope, OldScope, NextSName) when Scope =/= undefined; OldScope =/= undefined ->
    case Scope of
        next      -> NextSName;
        undefined -> OldScope;
        _         -> Scope
    end.


