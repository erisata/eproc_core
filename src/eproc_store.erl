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
%%  TODO: A lot of functionality is duplicated between store implementations. This behaviour should be reviewed.
%%
-module(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([
    ref/0, ref/2,
    supervisor_child_specs/1,
    get_instance/3,
    get_transition/4,
    get_message/3
]).
-export([
    add_instance/2,
    add_transition/3,
    set_instance_killed/3,
    set_instance_suspended/3,
    set_instance_resuming/4,
    set_instance_resumed/3,
    load_instance/2,
    load_running/2,
    attr_task/3
]).
-export([is_instance_terminated/1, apply_transition/2]).
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
%%  This function should register new persistent FSM.
%%  Additionally, the following should be performed:
%%
%%    * Unique FSM InstId should be generated.
%%    * Unique group should be generated, if group=new.
%%    * Fill instance id in related structures.
%%
-callback add_instance(
        StoreArgs   :: term(),
        Instance    :: #instance{}
    ) ->
        {ok, inst_id()}.


%%
%%  This function should register new transition for the FSM.
%%  Additionally, the following should be done:
%%
%%    * Add all related messages.
%%    * Terminate FSM, if the `inst_state` is substate of the `terminated` state.
%%    * suspend FSM, if `inst_state = suspended` and `interrupt = #interrupt{reason = R}`.
%%    * resume FSM, if instance state was `resuming` and new `inst_state = running`.
%%    * Handle attribute actions.
%%
%%  NOTE: For some of messages, a destination instance id will be unknown.
%%  These partially resolved destinations are in form of `{inst, undefined}`
%%  and are stored in messages and transition message references.
%%  A store implementation needs to resolve these message destinations
%%  after the message is stored, for example on first read (or each read).
%%
-callback add_transition(
        StoreArgs   :: term(),
        Transition  :: #transition{},
        Messages    :: [#message{}]
    ) ->
        {ok, inst_id(), trn_nr()}.


%%
%%  Mark instance as killed.
%%
-callback set_instance_killed(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        UserAction  :: #user_action{}
    ) ->
        {ok, inst_id()}.


%%
%%  Mark instance as suspended and initialize corresponing interrupt.
%%
-callback set_instance_suspended(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        Reason      :: #user_action{} | {fault, Reason :: term()} | {impl, Reason :: term()}
    ) ->
        {ok, inst_id()}.


%%
%%  This function is invoked when an attempt to resume the FSM made.
%%  It should check if the current status of the FSM is `suspended`
%%  or `resuming`. In other cases it should exit with an error.
%%  The following cases shoud be handled here:
%%
%%   1. Change `#instance.status` from `suspended` to `resuming`.
%%   2. Add the resume attempt to the active interrupt.
%%
-callback set_instance_resuming(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        StateAction :: unchanged | retry_last | {set, NewStateName, NewStateData, ResumeScript},
        UserAction  :: #user_action{}
    ) ->
        {ok, inst_id(), fsm_start_spec()} |
        {error, not_found | running | terminated} |
        {error, Reason :: term()}
    when
        NewStateName :: term(),
        NewStateData :: term(),
        ResumeScript :: script().


%%
%%  This function transfers the FSM from the `resuming` state to `running`.
%%  The following steps should be done for that:
%%
%%   1. Change `#instance.status` from `resuming` to `running`.
%%   2. Set transition number for the active interrupt number.
%%   3. The active interrupt should be marked as closed.
%%
-callback set_instance_resumed(
        StoreArgs   :: term(),
        InstId      :: inst_id(),
        TrnNr       :: trn_nr()
    ) ->
        ok |
        {error, Reason :: term()}.


%%
%%  Get instance with its current state and active interrupt.
%%
-callback load_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref()
    ) ->
        {ok, #instance{}} |
        {error, not_found}.


%%
%%  Return all FSMs, that should be started automatically on startup.
%%
-callback load_running(
        StoreArgs       :: term(),
        PartitionPred   :: fun((inst_id(), inst_group()) -> boolean())
    ) ->
        {ok, [{FsmRef :: fsm_ref(), StartSpec :: fsm_start_spec()}]}.


%%
%%  Perform attribute action.
%%
-callback attr_task(
        StoreArgs       :: term(),
        AttrModule      :: module(),
        AttrTask        :: term()
    ) ->
        Response :: term().


%%
%%  Get instance data by FSM reference (id or name).
%%  Several instances can be retrieved by providing a list of FsmRefs.
%%
%%  The parameter Query can have several values:
%%
%%  `header`
%%  :   Only main instance data is returned.
%%  `current`
%%  :   Returns FSM header information with the current state attached.
%%  `recent`
%%  :   Returns FSM header information with some recent state attached.
%%      The recent state can be retrieved easied, altrough can be suitable
%%      in some cases, like showing a list of instances with current state names.
%%
-callback get_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref() | [fsm_ref()],
        Query       :: header | current
    ) ->
        {ok, #instance{} | [#instance{}]} |
        {error, Reason :: term()}.


%%
%%  Get particular FSM transition.
%%  Any partial message destinations should be resolved when returing message references.
%%
-callback get_transition(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        TrnNr       :: trn_nr(),
        Query       :: all
    ) ->
        {ok, #transition{}} |
        {error, Reason :: term()}.


%%
%%  Get particular message by message id or message copy id.
%%  The returned message should contain message id instead of message copy id.
%%  Partial message destination should be resolved when returing the message.
%%
-callback get_message(
        StoreArgs   :: term(),
        MsgId       :: msg_id() | msg_cid(),
        Query       :: all
    ) ->
        {ok, #message{}} |
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
%%  This function returns an instance, possibly at some state.
%%  If instance not found or other error returns {error, Reason}.
%%
get_instance(Store, FsmRef, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_instance(StoreArgs, FsmRef, Query).


%%
%%  This function returns a transition of the specified FSM.
%%
get_transition(Store, FsmRef, TrnNr, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_transition(StoreArgs, FsmRef, TrnNr, Query).


%%
%%  This function returns a message by message id or message copy id.
%%
get_message(Store, MsgId, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_message(StoreArgs, MsgId, Query).



%% =============================================================================
%%  Functions for `eproc_fsm` and related modules.
%% =============================================================================

%%
%%  Stores new persistent instance, generates id for it,
%%  assigns a group and a name if not provided.
%%  Initial state should be provided in the `#instance.state` field.
%%
add_instance(Store, Instance = #instance{state = #inst_state{}}) ->
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
%%  Marks an FSM as resuming after it was suspended.
%%
set_instance_resuming(Store, FsmRef, StateAction, UserAction) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_resuming(StoreArgs, FsmRef, StateAction, UserAction).


%%
%%  Marks an FSM as running after it was suspended.
%%  This function is called from the running FSM process.
%%
set_instance_resumed(Store, InstId, TrnNr) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_resumed(StoreArgs, InstId, TrnNr).


%%
%%  Loads an instance and its current state.
%%  This function returns an instance with latest state.
%%
load_instance(Store, FsmRef) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_instance(StoreArgs, FsmRef).



%%
%%  Load all running FSMs. This function is used by a registry to get
%%  all FSMs to be restarted. Predicate PartitionPred can be used to
%%  filter FSMs.
%%
load_running(Store, PartitionPred) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_running(StoreArgs, PartitionPred).


%%
%%  Perform attribute task. User for performing
%%  data queries and synchronous actions.
%%
attr_task(Store, AttrModule, AttrTask) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:attr_task(StoreArgs, AttrModule, AttrTask).



%% =============================================================================
%%  Functions for `eproc_store` implementations.
%% =============================================================================

%%
%%  Checks if instance is terminated by status.
%%
is_instance_terminated(running)   -> false;
is_instance_terminated(suspended) -> false;
is_instance_terminated(resuming)  -> false;
is_instance_terminated(completed) -> true;
is_instance_terminated(failed)    -> true;
is_instance_terminated(killed)    -> true.


%%
%%  Replay transition on a specified state.
%%  Designed to be used with `lists:foldl`.
%%
apply_transition(Transition, InstState) ->
    #inst_state{
        inst_id = InstId,
        trn_nr = OldTrnNr,
        attrs_active = Attrs
    } = InstState,
    #transition{
        inst_id = InstId,
        number = TrnNr,
        sname = SName,
        sdata = SData,
        attr_last_id = AttrLastId,
        attr_actions = AttrActions
    } = Transition,
    TrnNr = OldTrnNr + 1,
    {ok, NewAttrs} = eproc_fsm_attr:apply_actions(AttrActions, Attrs, InstId, TrnNr),
    InstState#inst_state{
        trn_nr = TrnNr,
        sname = SName,
        sdata = SData,
        attr_last_id = AttrLastId,
        attrs_active = NewAttrs
    }.



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


