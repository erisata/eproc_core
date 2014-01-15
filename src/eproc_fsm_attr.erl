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


-record(attr_state, {
    attr_id :: integer(),
    attr    :: #attribute{},
    state   :: term()
}).
-record(state, {
    last_id :: integer(),
    attrs   :: [#attr_state{}]
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
        Action  :: #attr_action{},  % TODO: Wrong type
        Scope   :: term()
    ) ->
        {ok, Data :: term()} |  % TODO: Wrong response term
        {error, Reason :: term()}.

%%
%%  Attribute updated by user.
%%
-callback updated(
        Attribute   :: #attribute{},
        Action      :: #attr_action{}
    ) ->
        {ok, Data :: term()} |
        {error, Reason :: term()}.

%%
%%  Attribute removed by `eproc_fsm`.
%%
-callback removed(
        Attribute :: #attribute{},
        AttrState :: term()
    ) ->
        ok |
        {error, Reason :: term()}.

%%
%%  Store attribute information in the store.
%%  This callback is invoked in the context of `eproc_store`.
%%  TODO: Remove this, make this module a behaviour, that should
%%  be implemented by the store.
%%
-callback store(
        Store       :: store_ref(),
        Attribute   :: #attribute{},
        Args        :: term()
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
transition_end(InstId, TrnNr, NextSName, State = #state{last_id = LastAttrId, attrs = AttrStates}) ->
    ActionSpecs = erlang:erase('eproc_fsm_attr$actions'),
    {AttrStatesAfterActions, UserActions, _, NewAttrId} = lists:foldl(
        fun perform_action/2,
        {AttrStates, [], {InstId, TrnNr, NextSName}, LastAttrId},
        ActionSpecs
    ),
    {NextSName, AttrStatesAfterCleanup, CleanupActions} = lists:foldl(
        fun perform_cleanup/2,
        {NextSName, [], []},
        AttrStatesAfterActions
    ),
    AllActions = UserActions ++ CleanupActions,
    NewState = State#state{
        last_id = NewAttrId,
        attrs = AttrStatesAfterCleanup
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
            init_on_start(Other, SimilarStarted ++ Started);
        {error, Reason} ->
            erlang:throw({attr_init_failed, Reason})
    end.


%%
%%  Perform user actions on attributes.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_action(ActionSpec, {AttrStates, Actions, Context, LastAttrId}) ->
    {Module, Name, Action, Scope} = ActionSpec,
    case Name of
        undefined ->
            {NewAttrState, NewAction, NewAttrId} = perform_create(Module, Name, Action, Scope, Context, LastAttrId),
            {[NewAttrState | AttrStates], [NewAction | Actions], Context, NewAttrId};
        _ ->
            ByNameFun = fun (#attr_state{attr = #attribute{name = N}}) -> N =:= Name end,
            case lists:partition(ByNameFun, AttrStates) of
                {[], AttrStates} ->
                    {NewAttrState, NewAction, NewAttrId} = perform_create(Module, Name, Action, Scope, Context, LastAttrId),
                    {[NewAttrState | AttrStates], [NewAction | Actions], Context, NewAttrId};
                {[AttrState], OtherAttrStates} ->
                    {NewAttrState, NewAction} = perform_update(AttrState, Name, Action, Scope, Context),
                    {[NewAttrState | OtherAttrStates], [NewAction | Actions], Context, LastAttrId}
            end
    end.


%%
%%  Create new attribute.
%%
perform_create(Module, Name, Action, Scope, {InstId, TrnNr, NextSName}, LastAttrId) ->
    ResolvedScope = case Scope of
        next -> NextSName;
        _ -> Scope
    end,
    case Module:updated(Name, Action, ResolvedScope) of
        {ok, Data, State} ->
            NewAttrId = LastAttrId + 1,
            Attr = #attribute{
                inst_id = InstId,
                attr_id = NewAttrId,
                module = Module,
                name = Name,
                scope = ResolvedScope,
                data = Data,
                from = TrnNr,
                upds = [],
                till = undefined
            },
            AttrState = #attr_state{
                attr_id = NewAttrId,
                attr = Attr,
                state = State
            },
            AttrAction = #attr_action{
                module = Module,
                attr_id = NewAttrId,
                action = todo % TODO
            },
            {AttrState, AttrAction, NewAttrId};
        {error, Reason} ->
            erlang:throw({attr_create_failed, Reason})
    end.


%%
%%  Update existing attribute.
%%
perform_update(AttrState, Name, Action, Scope, {InstId, TrnNr, NextSName}) ->
    {}. % TODO


%%
%%  Cleanup attributes, that became out-of-scope.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_cleanup(AttrState, {SName, Attrs, Actions}) ->
    #attr_state{attr = Attr, state = State} = AttrState,
    #attribute{attr_id = AttrId, module = Module, scope = Scope} = Attr,
    case eproc_fsm:state_in_scope(SName, Scope) of
        true ->
            {SName, [Attr | Attrs], Actions};
        false ->
            case Module:removed(Attr, State) of
                ok ->
                    Action = #attr_action{
                        module = Module,
                        attr_id = AttrId,
                        action = {remove, {scope, SName}}
                    },
                    {SName, Attrs, [Action | Actions]};
                {error, Reason} ->
                    erlang:throw({attr_cleanup_failed, Reason})
            end
    end.


