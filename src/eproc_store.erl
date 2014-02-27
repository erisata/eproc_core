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
%%  Main interface for a store implementation. The core engine is always using
%%  this module to access the database. Several implementations of this interface
%%  are provided. The `eproc_core` provides ETS and Mnesia based implementations.
%%  Riak based implementation is provided by the `eproc_riak` component.
%%
-module(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([ref/0, ref/2, supervisor_child_specs/1, get_instance/3]).
-export([
    add_instance/2,
    add_transition/3,
    set_instance_killed/3,
    set_instance_suspended/3,
    set_instance_resumed/4,
    set_instance_state/6,
    load_instance/2,
    load_running/2
]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  This callback should return a list of supervisor child specifications
%%  used to start the store.
%%
-callback supervisor_child_specs(
        StoreArgs   :: term()
    ) ->
        {ok, list()}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback add_instance(
        StoreArgs   :: term(),
        Instance    :: #instance{}
    ) ->
        {ok, inst_id()}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback add_transition(
        StoreArgs   :: term(),
        Transition  :: #transition{},
        Messages    :: [#message{}]
    ) ->
        {ok, inst_id(), trn_nr()}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback set_instance_killed(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        UserAction  :: #user_action{}
    ) ->
        {ok, inst_id()}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback set_instance_suspended(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        Reason      :: #user_action{} | {fault, Reason :: term()} | {impl, Reason :: binary()}
    ) ->
        {ok, inst_id()}.


%%
%%  This function is invoked when the FSM is resumed. It should
%%  change data only if the current status of the FSM is `suspended`.
%%  The following cases shoud be handled here:
%%
%%   1. State was not updated while FSM was suspended. In this case
%%      the FSM status should be changed to "running" and the `inst_susp`
%%      record should be closed by setting the `resumed` field.
%%
%%   2. State was updated while FSM was suspended. In this case the
%%      FSM status should be left unchanged (`suspended`) and the
%%      `inst_susp` should be closed by adding the user action to the
%%      front of the resume list. The FSM status will be changed later
%%      with invokation of `add_transition`, used to create new transition
%%      reflecting updated state.
%%
-callback set_instance_resumed(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        UserAction  :: #user_action{},
        TransitionFun
    ) ->
        {ok, inst_id(), fsm_start_spec()} |
        {error, not_found | running | terminated} |
        {error, Reason :: term()}
    when
        TransitionFun :: fun (
                (#instance{}, #inst_susp{}) ->
                (none | {add, #transition{}, #message{}} | {error, term()})
            ).


%%
%%  TODO: Describe, what should be done here.
%%
-callback set_instance_state(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        UserAction  :: #user_action{},
        StateName   :: term(),
        StateData   :: term(),
        AttrActions :: [#attr_action{}]
    ) ->
        {ok, inst_id()} |
        {error, Reason :: term()}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback load_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref()
    ) ->
        {ok, #instance{}} |
        {error, not_found}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback load_running(
        StoreArgs       :: term(),
        PartitionPred   :: fun((inst_id(), inst_group()) -> boolean())
    ) ->
        {ok, [{FsmRef :: fsm_ref(), StartSpec :: fsm_start_spec()}]}.


%%
%%  TODO: Describe, what should be done here.
%%
-callback get_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        Query       :: header
    ) ->
        {ok, #instance{}} |
        {error, Reason :: term()}.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Returns supervisor child specifications, that should be used to
%%  start the store.
%%
-spec supervisor_child_specs(Store :: store_ref()) -> {ok, list()}.

supervisor_child_specs(Store) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:supervisor_child_specs(StoreArgs).


%%
%%  Returns the default store reference.
%%
-spec ref() -> {ok, store_ref()}.

ref() ->
    {ok, {StoreMod, StoreArgs}} = eproc_core_app:store_cfg(),
    ref(StoreMod, StoreArgs).



%%
%%  Create a store reference.
%%
-spec ref(module(), term()) -> {ok, store_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%  This function returns an instance with single (or zero) transitions.
%%  If instance not found or other error returns {error, Reason}.
%%
get_instance(Store, InstId, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_instance(StoreArgs, InstId, Query).



%% =============================================================================
%%  Functions for `eproc_fsm` and related modules.
%% =============================================================================

%%
%%  Stores new persistent instance, generates id for it,
%%  assigns a group and a name if not provided.
%%
add_instance(Store, Instance) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:add_instance(StoreArgs, Instance).


%%
%%  Add a transition for existing FSM instance.
%%  Messages received or sent during the transition are also saved.
%%  Instance state is updated according to data in the transition.
%%
add_transition(Store, Transition, Messages) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:add_transition(StoreArgs, Transition, Messages).


%%
%%  Marks an FSM instance as killed.
%%
set_instance_killed(Store, FsmRef, UserAction) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_killed(StoreArgs, FsmRef, UserAction).


%%
%%  Marks an FSM instance as suspended.
%%
set_instance_suspended(Store, FsmRef, Reason) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_suspended(StoreArgs, FsmRef, Reason).


%%
%%  Marks an FSM as running after it was suspended.
%%
set_instance_resumed(Store, FsmRef, UserAction, TransitionFun) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_resumed(StoreArgs, FsmRef, UserAction, TransitionFun).


%%
%%  Updates state "manually" for a suspended FSM.
%%
set_instance_state(Store, FsmRef, UserAction, StateName, StateData, AttrActions) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_state(StoreArgs, FsmRef, UserAction, StateName, StateData, AttrActions).


%%
%%  Loads an instance and its current state.
%%  This function returns an instance with single (or zero) transitions.
%%  The transition, if returned, stands for the current state of the FSM.
%%  The transition is also filled with the active props, keys and timers.
%%
load_instance(Store, InstId) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_instance(StoreArgs, InstId).


%%
%%  Load all running FSMs. This function is used by a registry to get
%%  all FSMs to be restarted. Predicate PartitionPred can be used to
%%  filter FSMs.
%%
load_running(Store, PartitionPred) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_running(StoreArgs, PartitionPred).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve the provided (optional) store reference.
%%
resolve_ref({StoreMod, StoreArgs}) ->
    {ok, {StoreMod, StoreArgs}};

resolve_ref(undefined) ->
    ref().


