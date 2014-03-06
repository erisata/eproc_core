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
%%  FSM attribute is a mechanism for extending FSM at a system level.
%%  Several extensions are provided within `eproc_core`, and other
%%  implementations can also be provided by an user.
%%
-module(eproc_fsm_attr).
-compile([{parse_transform, lager_transform}]).
-export([action/4, action/3, make_event/3]).
-export([apply_actions/4]).
-export([init/3, transition_start/4, transition_end/4, event/2]).
-include("eproc.hrl").


-record(attr_ctx, {
    attr_id :: integer(),       %%  Attribute ID.
    attr    :: #attribute{},    %%  Attribute info.
    state   :: term()           %%  Runtime state of the attribute.
}).

-record(state, {
    last_id :: integer(),       %%  Last used attribute ID.
    attrs   :: [#attr_ctx{}]    %%  Contexts for all active attributes of the FSM.
}).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  Invoked when FSM started or restarted.
%%
-callback init(
        ActiveAttrs :: [#attribute{}]
    ) ->
        {ok, [{Attribute, AttrState}]} |
        {error, Reason}
    when
        Attribute :: #attribute{},
        AttrState :: term(),
        Reason :: term().

%%
%%  Attribute created.
%%  This callback will always be called in the scope of transition.
%%
-callback handle_created(
        Attribute   :: #attribute{},
        Action      :: term(),
        Scope       :: term()
    ) ->
        {create, Data, State} |
        {error, Reason}
    when
        Data :: term(),
        State :: term(),
        Reason :: term().

%%
%%  Attribute updated by user.
%%  This callback will always be called in the scope of transition.
%%
-callback handle_updated(
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
%%  This callback will always be called in the scope of transition.
%%
-callback handle_removed(
        Attribute :: #attribute{},
        AttrState :: term()
    ) ->
        ok |
        {error, Reason}
    when
        Reason :: term().


%%
%%  Notifies about an event, received by the attribute.
%%  This handler can update attribute's runtime state and
%%  optionally initiate an FSM transition by providing its
%%  trigger.
%%
-callback handle_event(
        Attribute   :: #attribute{},
        AttrState   :: term(),
        Event       :: term()
    ) ->
        {handled, NewAttrState} |
        {trigger, Trigger, Action} |
        {error, Reason}
    when
        NewAttrState :: term(),
        NewAttrData :: term(),
        Trigger     :: #trigger_spec{},
        Action ::
            {update, NewAttrData, NewAttrState} |
            {remove, Reason},
        Reason :: term().



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
%%  Returns a message, that can be sent to the FSM process. It will be recognized
%%  as a message sent to the particular attribute and its handler.
%%
make_event(_Module, AttrId, Event) ->
    {ok, {'eproc_fsm_attr$event', AttrId, Event}}.



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
    {ok, AllActions, NewAttrId, NewState}.


%%
%%  Invoked, when the FSM receives
%%
event({'eproc_fsm_attr$event', AttrId, Event}, State = #state{attrs = AttrCtxs}) ->
    case lists:keyfind(AttrId, #attr_ctx.attr_id, AttrCtxs) of
        false ->
            lager:debug("Ignoring attribute event with unknown id=~p", [attr_id]),
            {handled, State};
        AttrCtx ->
            case process_event(AttrCtx, Event) of
                {handled, NewAttrCtx} ->
                    NewAttrCtxs = lists:keyreplace(AttrId, #attr_ctx.attr_id, AttrCtxs, NewAttrCtx),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {handled, NewState};
                {trigger, removed, Trigger, AttrAction} ->
                    NewAttrCtxs = lists:keydelete(AttrId, #attr_ctx.attr_id, AttrCtxs),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {trigger, NewState, Trigger, AttrAction};
                {trigger, NewAttrCtx, Trigger, AttrAction} ->
                    NewAttrCtxs = lists:keyreplace(AttrId, #attr_ctx.attr_id, AttrCtxs, NewAttrCtx),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {trigger, NewState, Trigger, AttrAction}
            end
    end;

event(_Event, _State) ->
    unknown.



%% =============================================================================
%%  Functions for `eproc_store`.
%% =============================================================================

%%
%%  Replays actions of the specific transition on initial attributes.
%%
-spec apply_actions(
        AttrActions :: [#attr_action{}] | undefined,
        Attributes  :: [#attribute{}],
        InstId      :: inst_id(),
        TrnNr       :: trn_nr()
    ) ->
        {ok, [#attribute{}]}.

apply_actions(undefined, Attributes, _InstId, _TrnNr) ->
    {ok, Attributes};

apply_actions(AttrActions, Attributes, InstId, TrnNr) ->
    FoldFun = fun (Action, Attrs) ->
        apply_action(Action, Attrs, InstId, TrnNr)
    end,
    NewAttrs = lists:foldl(FoldFun, Attributes, AttrActions),
    {ok, NewAttrs}.


%%
%%  Replays single attribute action.
%%  Returns a list of active attributes after applying the provided attribute action.
%%  Its an internal function, helper for `apply_actions/4`.
%%
apply_action(#attr_action{module = Module, attr_id = AttrId, action = Action}, Attrs, InstId, TrnNr) ->
    case Action of
        {create, Name, Scope, Data} ->
            NewAttr = #attribute{
                inst_id = InstId,
                attr_id = AttrId,
                module = Module,
                name = Name,
                scope = Scope,
                data = Data,
                from = TrnNr,
                upds = [],
                till = undefined,
                reason = undefined
            },
            [NewAttr | Attrs];
        {update, NewScope, NewData} ->
            Attr = #attribute{upds = Upds} = lists:keyfind(AttrId, #attribute.attr_id, Attrs),
            NewAttr = Attr#attribute{
                scope = NewScope,
                data = NewData,
                upds = [TrnNr | Upds]
            },
            lists:keyreplace(AttrId, #attribute.attr_id, Attrs, NewAttr);
        {remove, _Reason} ->
            lists:keydelete(AttrId, #attribute.attr_id, Attrs)
    end.



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
    NewAttrId = LastAttrId + 1,
    NewAttribute = #attribute{
        inst_id = InstId,
        attr_id = NewAttrId,
        module = Module,
        name = Name,
        scope = ResolvedScope,
        data = undefined,
        from = TrnNr,
        upds = [],
        till = undefined
    },
    case Module:handle_created(NewAttribute, Action, ResolvedScope) of
        {create, AttrData, AttrState} ->
            AttrCtx = #attr_ctx{
                attr_id = NewAttrId,
                attr = NewAttribute#attribute{data = AttrData},
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
perform_update(AttrCtx, Action, Scope, {_InstId, TrnNr, NextSName}) ->
    #attr_ctx{
        attr = Attribute,
        state = AttrState
    } = AttrCtx,
    #attribute{
        attr_id = AttrId,
        module = Module,
        scope = OldScope,
        upds = Upds
    } = Attribute,
    ResolvedScope = resolve_scope(Scope, OldScope, NextSName),
    case Module:handle_updated(Attribute, AttrState, Action, Scope) of
        {update, NewData, NewState} ->
            AttrAction = #attr_action{
                module = Module,
                attr_id = AttrId,
                action = {update, ResolvedScope, NewData}
            },
            NewAttribute = Attribute#attribute{
                data = NewData,
                scope = ResolvedScope,
                upds = [TrnNr | Upds]
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
    case eproc_fsm:is_state_in_scope(SName, Scope) of
        true ->
            {SName, [AttrCtx | AttrCtxs], Actions};
        false ->
            case Module:handle_removed(Attr, State) of
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
process_event(AttrCtx, Event) ->
    #attr_ctx{attr = Attribute, state = AttrState} = AttrCtx,
    #attribute{attr_id = AttrId, module = Module, scope = Scope} = Attribute,
    case Module:handle_event(Attribute, AttrState, Event) of
        {handled, NewAttrState} ->
            NewAttrCtx = AttrCtx#attr_ctx{state = NewAttrState},
            {handled, NewAttrCtx};
        {trigger, Trigger, {remove, Reason}} when is_record(Trigger, trigger_spec) ->
            AttrAction = #attr_action{
                module = Module,
                attr_id = AttrId,
                action = {remove, {user, Reason}}
            },
            {trigger, removed, Trigger, AttrAction};
        {trigger, Trigger, {update, NewAttrData, NewAttrState}} when is_record(Trigger, trigger_spec) ->
            NewAttrCtx = AttrCtx#attr_ctx{
                attr = Attribute#attribute{data = NewAttrData},
                state = NewAttrState
            },
            AttrAction = #attr_action{
                module = Module,
                attr_id = AttrId,
                action = {update, Scope, NewAttrData}
            },
            {trigger, NewAttrCtx, Trigger, AttrAction};
        {error, Reason} ->
            erlang:throw({attr_event_failed, Reason})
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


