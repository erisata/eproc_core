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
%%  TODO: Description.
%%
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
-export([init/3, transition_start/2, transition_end/3, event/2]).
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
        Action  :: #attr_action{},
        Scope   :: term()
    ) ->
        {ok, Data :: term()} |
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
%%
%%
action(Module, Name, Action, Scope) ->
    eproc_fsm:register_attr_action(Module, Name, Action, Scope).


%%
%%
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
transition_start(SName, State) ->
    erlang:put('eproc_fsm_attr$actions', []),
    {ok, State}.


%%
%%  Invoked at the end of each transition.
%%
transition_end(NewSName, OldSName, State = #state{attrs = AttrStates}) ->
    ActionSpecs = erlang:erase('eproc_fsm_attr$actions'),
    {AttrStatesAfterActions, UserActions} = lists:foldl(
        fun perform_action/2,
        {AttrStates, []},
        ActionSpecs
    ),
    {NewSName, AttrStatesAfterCleanup, CleanupActions} = lists:foldl(
        fun perform_cleanup/2,
        {NewSName, [], []},
        AttrStatesAfterActions
    ),
    AllActions = UserActions ++ CleanupActions,
    NewState = State#state{attrs = AttrStatesAfterCleanup},
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
perform_action(Action, Attrs) ->
    % TODO
    Attrs.


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


