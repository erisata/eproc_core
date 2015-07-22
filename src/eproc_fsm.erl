%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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

%%%
%%% Main behaviour to be implemented by a user of the `eproc`
%%% =========================================================
%%%
%%% This module designed by taking into account UML FSM definition
%%% as well as the Erlang/OTP `gen_fsm`. The following is the list
%%% of differences comparing it to `gen_fsm`:
%%%
%%%   * State name supports substates and orthogonal states.
%%%   * Callback `Module:handle_state/3` is used instead of `Module:StateName/2-3`.
%%%     This allows to have substates and orthogonal states.
%%%   * Has support for state entry and exit actions.
%%%     State entry action is convenient for setting up timers and keys.
%%%   * Has support for scopes. The scopes can be used to manage timers and keys.
%%%   * Supports automatic state persistence.
%%%
%%% It is recomended to name version explicitly when defining state.
%%% It can be done as follows:
%%%
%%%     -record(state, {
%%%         version = 1,
%%%         ...
%%%     }).
%%%
%%%
%%% How `eproc_fsm` callbacks are invoked in different scenarios
%%% ------------------------------------
%%%
%%% New FSM created, started and an initial event received
%%% :
%%%     On creation of the persistent FSM inialization in performed:
%%%
%%%       * `init(Args)`
%%%
%%%     then process is started, the following callbacks are used to
%%%     possibly upgrade and initialize process runtime state:
%%%
%%%       * `code_change(state, StateName, StateData, undefined)`
%%%       * `init(InitStateName, StateData)`
%%%
%%%     and then the first event is received and the following callbacks invoked:
%%%
%%%       * `handle_state(InitStateName, {event, Message} | {sync, From, Message}, StateData)`
%%%       * `handle_state(NewStateName, {entry, InitStateName}, StateData)`
%%%
%%% FSM process terminated
%%% :
%%%       * `terminate(Reason, StateName, StateData)`
%%%
%%% FSM is restarted or resumed after being suspended
%%% :
%%%       * `code_change(state, StateName, StateData, undefined)`
%%%       * `init(StateName, StateData)`
%%%
%%% FSM upgraded in run-time
%%% :
%%%       * `code_change(OldVsn, StateName, StateData, Extra)`
%%%
%%% Event initiated a transition (`next_state`)
%%% :
%%%       * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%%       * `handle_state(StateName, {exit, NextStateName}, StateData)`
%%%       * `handle_state(NextStateName, {entry, StateName}, StateData)`
%%%
%%% Event with no transition (`same_state`)
%%% :
%%%       * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%%
%%% Event initiated a termination (`final_state`)
%%% :
%%%       * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%%       * `handle_state(StateName, {exit, FinalStateName}, StateData)`
%%%
%%%
%%% Dependencies
%%% ------------------------------------
%%%
%%% This section lists modules, that can be used together with this module.
%%% All of them are optional and are references using options. Some functions
%%% require specific dependencies, but these functions are more for convenience.
%%%
%%% `eproc_registry`
%%% :   can be used as a process registry, a supervisor and a process loader.
%%%     This component is used via options: `start_spec` from the create options,
%%%     `register` from the start options and `registry` from the common options.
%%%     Functions `send_create_event/3` and `sync_send_create_event/4` can only
%%%     be called if FSM used with the registry.
%%%
%%% `eproc_limits`
%%% :   can be used to limit FSM restarts, transitions or sent messages.
%%%     This component is only used if start option `limit_*` are provided.
%%%
%%%
%%% Common FSM options
%%% ------------------------------------
%%%
%%% The following are the options, that can be provided for most of the
%%% functions in this module. Meaning of these options is the same in all cases.
%%% Description of each function states, which of these options are used in that
%%% function and other will be ignored.
%%%
%%% `{store, StoreRef}`
%%% :   a store to be used by the FSM. If this option not provided, a store
%%%     specified in the `eproc_core` application environment is used.
%%%
%%% `{registry, StoreRef}`
%%% :   a registry to be used by the instance. If this option not provided, a registry
%%%     specified in the `eproc_core` application environment is used. `eproc_core` can
%%%     have no registry specified. In that case the registry will not be used.
%%%
%%% `{timeout, Timeout}`
%%% :   Timeout for the function, 5000 (5 seconds) is the default.
%%%
%%% `{user, (User :: (binary() | #user{})) | {User :: (binary() | #user{}), Comment :: binary()}`
%%% :   indicates a user initiaten an action. This option is mainly
%%%     used for administrative actions: kill, suspend and resume.
%%%
%%%
%%% To be done in this module (TODO):
%%%
%%%   * Attachment support.
%%%   * Implement FSM crash listener (`eproc_fsm_mgr`?).
%%%   * Check if InstId can be non-integer.
%%%   * Add support for transient processes, that are not registered to the store.
%%%   * Add `ignore` handling for `handle_cast` and `handle_call`.
%%%   * Implement persistent process linking. It could work as follows:
%%%         * Processes are activated only when all linked (related) processes are online.
%%%         * When becoming online, linked processes start to monitor each other.
%%%         * Subprocesses can be one of a ways to link processes.
%%%   * Implement sub-fsm modules, that work in the same process.
%%%   * Implement wakeup event, that would be sent when the FSM becomes online. Maybe init/* can be used instead?
%%%   * Do we need the initial event at all? Maybe the creation args are enough?
%%%
-module(eproc_fsm).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).

%%
%%  Functions to be used by FSM implementations on the client-side.
%%  I.e. they should be used in API functions of the specific FSM.
%%
-export([
    create/3, start_link/3, start_link/2, id/0, group/0, name/0,
    send_create_event/4, sync_send_create_event/4,
    send_event/3, send_event/2,
    self_send_event/2, self_send_event/1,
    sync_send_event/3, sync_send_event/2,
    kill/2, suspend/2, resume/2, update/5,
    is_online/2, is_online/1
]).

%%
%%  Functions to be used by the specific FSM implementations
%%  in the callback (process-side) functions.
%%
-export([
    reply/2, suspend/1
]).

%%
%%  APIs for related `eproc` modules.
%%
-export([
    is_fsm_ref/1,
    is_state_in_scope/2,
    is_state_valid/1,
    is_next_state_valid/1,
    is_next_state_valid/2,
    derive_next_state/2,
    register_sent_msg/6,
    register_resp_msg/7,
    registered_send/5,
    registered_sync_send/5,
    resolve_start_spec/2,
    resolve_event_type/2,
    resolve_event_type_const/3
]).

%%
%%  Callbacks for `gen_server`.
%%
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%
%%  Type exports.
%%
-export_type([name/0, id/0, group/0, state_event/0, state_name/0, state_scope/0, state_data/0, start_spec/0]).

%%
%%  Internal things...
%%
-include("eproc.hrl").
-define(DEFAULT_TIMEOUT, 5000).
-define(LIMIT_PROC(IID), {'eproc_fsm$limits', IID}).
-define(LIMIT_RES, res).
-define(LIMIT_TRN, trn).
-define(LIMIT_MSG_ALL, {msg, all}).
-define(LIMIT_MSG_DST(D), {msg, {dst, D}}).
-define(MSGCID_REQUEST(I, T), {I, T, 0, recv}).
-define(MSGCID_REPLY(I, T),   {I, T, 1, sent}).
-define(MSGCID_SENT(I, T, M), {I, T, M, sent}).
-define(MSGCID_RECV(I, T, M), {I, T, M, recv}).


-type name() :: {via, Registry :: module(), InstId :: inst_id()}.
-opaque id()  :: {InstNr :: integer(), Domain :: atom()}.
-opaque group() :: id().

%%
%%  An event, received by the FSM.
%%
-type state_event() :: term().

%%
%%  State name describes current state of the FSM. The `eproc_fsm` supports
%%  nested and orthogonal states and state name is sued to describe them.
%%
%%  State name is always a list, where first element denotes a state and
%%  all the rest elements stand for substate. I.e. if we have a state
%%  `active` its substate `running` with substates `online` and `offline`,
%%  the state `online` is expresses as `[active, running, online]` and the
%%  offline state is expressed as `[active, running, offline]`.
%%
%%  The root state is `[]`. This state is entered when new FSM is created
%%  and it is never exited till termination of the FSM. Nevertheless, the
%%  entry and exit actions are not invoked for the root state.
%%
%%  Elements of the state name should be atoms or records (tagged tuples).
%%  The atom (or the name of the record) stands for the unqualified (local)
%%  name of the state. While atoms are used to describe nested states, records
%%  are used to describe orthogonal states. Each field of the record has the
%%  same structure as the entire state name. I.e. it can have nested and orthogonal
%%  states. For example, lets assume we have state `completed` with two orthogonal
%%  regions, where first region have substates `done`, `failed` and `killed`,
%%  and the second region - `available` and `archived`.
%%  The state "`done` and `archived`" can be expresses as `[{completed, [done], [archived]}]`.
%%
%%  The FSM callback can return ortogonal state with some of its regions
%%  marked as unchanged ('_' instead of region state). The corresponding
%%  exit and entry events will be called with the same wildcarded state
%%  name, although the final state will be derived by replacing wildcards
%%  with the previous states of the corresponding regions. This allows
%%  handle_state callback implementation to determine, which state is entered
%%  or exited. Wildcarded transition is only allowed within the same orthogonal
%%  state, i.e. only regions can differ from the previous state.
%%
%%  TODO: Consider to use atoms for simple states and tuples for nested
%%      states, like {active, {running, online}}. It whould allow to define
%%      state machine type (declare allowed states), and event would be more
%%      consistent with UML and state regions.
%%
-type state_name() :: list().

%%
%%  State scope is used to specify validity of some FSM attributes. Currently the
%%  scope needs to be specified for timers and keys. I.e. when the FSM exits the
%%  specified state (scope), the corresponding timers and keys will be terminated.
%%
%%  The state scope has a structure similar to state name, except that it supports
%%  wildcarding. Main use case for wildcarding is orthogonal states, but it can
%%  be used with nested states also.
%%
%%  In general, scope is a state, which is not necessary the leaf state in the
%%  tree of possible states. For nested states, the scope can be seen as a state
%%  prefix, for which the specified timer or key is valid. I.e. looking at the
%%  example provided in the description of `state_name`, all of `[]`, `[active]`,
%%  `[active, running]` and `[active, running, online]` can be scopes and the
%%  state `[active, running, online]` will be in all of these scopes.
%%  Similarly, the state `[active, running, offline]` will be in scopes `[]`, `[active]`
%%  and `[active, running]` but not in `[active, running, online]` (from the scopes listed above).
%%
%%  When used with orthogonal states, scopes can be used to specify in one
%%  of its regions. E.g. if the state 'done' should be specified as a scope,
%%  the following term can be used: `[{completed, [done], []}]`. I.e. the second
%%  region can be in any substate.
%%
%%  The atom `_` can be used for wildcarding instead of `[]`. It was introduced to
%%  maintain some similarity with mnesia queries. Additionally, the `_` atom can be
%%  used to wildcard a state element, that is not at the end of the path.
%%
%%  Scope for a state, that has orthogonal regions can be expressed in several ways.
%%  Wildcards can be specified for all of its regions, e.g. `[{completed, '_', '_'}]`
%%  or `[{completed, [], []}]`. Additionally, a shortcut notation can be used for
%%  it: only name can be specified in the scope, if all the regions are going to be ignored.
%%  I.e. the above mentioned scope can be expressed as `[completed]`.
%%
-type state_scope() :: list().

%%
%%  Internal state of the callback module. The state is considered
%%  opaque by the `eproc_fsm`, but its usually an instance of the
%%  #state{} record in the user module.
%%
-type state_data() :: term().


%%
%%  FSM start specification.
%%  See `create/3` for more details.
%%
-opaque start_spec()  ::
    {default, StartOpts :: list()} |
    {mfa, MFArgs ::mfargs()}.



%% =============================================================================
%%  Internal state of the module.
%% =============================================================================

%%
%%  Internal state of the `eproc_fsm`.
%%
-record(state, {
    inst_id     :: inst_id(),       %% Id of the current instance.
    module      :: module(),        %% Implementation of the user FSM.
    sname       :: state_name(),    %% User FSM state name.
    sdata       :: state_data(),    %% User FSM state data.
    rt_field    :: integer(),       %% Runtime data field in the sdata.
    rt_default  :: term(),          %% Default value for the runtime field.
    trn_nr      :: trn_nr(),        %% Number of the last processed transition.
    attrs       :: term(),          %% State for the `eproc_fsm_attr` module.
    registry    :: registry_ref(),  %% A registry reference.
    store       :: store_ref(),     %% A store reference.
    lim_res     :: term(),          %% Instance limits: restart counter limit specs.
    lim_trn     :: term(),          %% Instance limits: transition counter limit specs.
    lim_msg_all :: term(),          %% Instance limits: counter limit specs for all sent messages.
    lim_msg_dst :: term()           %% Instance limits: counter limit specs for sent messages by destination.
}).


%%
%%  Structures for message registration.
%%
-record(msg_reg, {
    dst         :: event_src(),
    sent_cid    :: msg_cid(),
    sent_msg    :: term(),
    sent_type   :: binary(),
    sent_time   :: timestamp(),
    resp_cid    :: undefined | msg_cid(),
    resp_msg    :: undefined | term(),
    resp_type   :: undefined | binary(),
    resp_time   :: undefined | timestamp()
}).
-record(msg_regs, {
    inst_id     :: inst_id(),
    trn_nr      :: trn_nr(),
    next_msg_nr :: integer(),
    registered  :: [#msg_reg{}]
}).



%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  Invoked when creating (not starting) the persistent FSM. The callback
%%  is invoked NOT in the process of the FSM.
%%
%%  Parameters:
%%
%%  `Args`
%%  :   is the value passed as the `Args` parameter to the `create/3`,
%%      `send_create_event/5` or `sync_send_create_event/5` function.
%%
%%  The function needs to return `StateData` - internal state of the process.
%%  The created instance will be in state [].
%%
-callback init(
        Args :: term()
    ) ->
        {ok, StateData}
    when
        StateData :: state_data().


%%
%%  This function is invoked on each (re)start of the FSM. On the first start
%%  this callback is always invoked after the `init/1` callback.
%%
%%  In this function the FSM can initialize its run-time resources:
%%  start or link to processes, etc. This callback is invoked in the
%%  context of the FSM process.
%%
%%  Parameters:
%%
%%  `StateName`
%%  :   is the state name loaded from the persistent store or returned
%%      by the `init/1` callback, if initialization is performed for a new instance.
%%  `StateData`
%%  :   is the corresponding persistent state data.
%%
%%  The callback should `{ok, RuntimeField, RuntimeData}` to initialize runtime data
%%  and `ok` if runtime data functionality is not used. The returned RuntimeData is assigned
%%  to a field with index RuntimeField. This functionality assumes StateData to be a tuple.
%%
%%  The RuntimeField is also used later for rewriting the runtime data field to the default
%%  value when writing it to a database. The default value is assumed to be a value, that
%%  was assigned to the corresponding field before `init/2`. Usually it is specified in the
%%  record definition or the `init/1` function. The RuntimeField can be changed in the
%%  `code_change` function.
%%
-callback init(
        StateName :: state_name(),
        StateData :: state_data()
    ) ->
        ok |
        {ok, RuntimeField, RuntimeData}
    when
        RuntimeField :: integer(),
        RuntimeData :: state_data().


%%
%%  This function handles events coming to the FSM. It is also used
%%  to handle state entry and exit actions.
%%
%%  Parameters:
%%
%%  `StateName`
%%  :   is the name of the state, at which an event occured.
%%  `Trigger`
%%  :   indicates, wether this callback is invoked to handle an event, synchronous
%%      event, timer, state entry or state exit:
%%
%%      `{event, Message}`
%%      :   indicates an event `Message` sent to the FSM asynchronously.
%%          It is done by calling `send_event/2-3` or corresponding create event.
%%      `{sync, From, Message}`
%%      :   indicates an event `Message` sent by `From` to the FSM synchronously.
%%          It is done by calling `sync_send_event/2-3` or corresponding create event.
%%      `{info, Message}`
%%      :   indicates unknown message, received by the FSM. This message is
%%          similar to the `get_fsm`s `handle_info` callback.
%%          Its an asynchronous message.
%%      `{timer, Message}`
%%      :   indicates a time event `Message`, that was fired by a timer.
%%          This event is generated by the `eproc_timer` module.
%%      `{exit, NextStateName}`
%%      :   indicates that a transition was made from the `StateName` to the
%%          `NextStateName` and now we are exiting the `StateName`.
%%      `{entry, PrevStateName}`
%%      :   indicates that a transition was made from the `PrevStateName` to the
%%          `StateName` and now we are entering the `StateName`. A handler for
%%          state entry is a good place to set up timers that shouls be valid in
%%          that state.
%%
%%      The `event`, `sync`, `info` and `timer` tuples all indicate transition triggers and are
%%      handled by the `eproc_core` application. Additional triggers can be added by implementing
%%      FSM attribute handlers. The generic structure of a trigger tuple (not taking exit and entry)
%%      is the following:
%%
%%      {Type, Message}
%%      :   for asynchronous messages.
%%      {Type, From, Message}
%%      :   for synchronous messages.
%%      {Type, Source, Message}
%%      :   for asynchronous messages when event source is needed.
%%      {Type, Source, From, Message}
%%      :   for synchronous messages when event source is needed.
%%
%%      The particular tuple structure should be defined in the module providing
%%      the attribute handler implementation.
%%
%%  `StateData`
%%  :   contains internal state of the FSM.
%%
%%  If the function was invoked with asynchronous trigger (like `event`, `timer` or `info`),
%%  the function should return one of the following:
%%
%%  `{same_state, NewStateData}`
%%  :   to indicate, that transition is to the the same state. In this case, corresponding
%%      state exit and entry callbacks will not be invoked.
%%  `{next_state, NextStateName, NewStateData}`
%%  :   indicates a transition to the next state. Next state can also be the current state,
%%      but in this case state exit/entry callbacks will be invoked anyway.
%%  `{final_state, FinalStateName, NewStateData}`
%%  :   indicates a transition to the final state of the FSM. I.e. FSM is terminated after
%%      this transition.
%%
%%  In the case of synchronous events `{sync, From, Message}`, the callback can return all the
%%  responses listed above, if reply to the caller was sent explicitly using function `reply/2`.
%%  If reply was not sent explicitly, the terms tagged with `reply_same`, `reply_next` and `reply_final`
%%  should be used to send a reply and do the transition. Meaning of these response terms are
%%  the same as for the `same_state`, `next_state` and `final_state` correspondingly.
%%
%%  If the callback was invoked to handle state exit, the response term should be
%%  `{ok, NewStateData}`.
%%
%%  If the callback was invoked to handle state entry, the response term can be one of the following:
%%
%%  `{ok | same_state, NewStateData}`
%%  :   indicates, that the entry to the state if done.
%%  `{next_state, NextStateName, NewStateData}`
%%  :   says, that other state should be entered instead of this one.
%%      This is usefull for entering substates in a composite state.
%%      I.e, the source state can issue transition to the composite state withouth
%%      knowing its substates. The target state then enters its own initial state
%%      as needed. 'eproc_fsm' will only call entry callback for the new state,
%%      the exit and event callbacks will not be called for the current state.
%%  `{final_state, FinalStateName, NewStateData}`
%%  :   indicates, that the FSM is terminating. As in the case of the `next_state`,
%%      this case is also usefull when implementing composite states. No other callbacks
%%      will be called after this response.
%%
%%  The state exit action is not invoked for the initial transition. The initial transition
%%  can be recognized by the state entry action, it will be invoked with `[]` as a PrevStateName
%%  or the state name as returned by the `init/2` callback.
%%  Similarly, the entry action is not invoked for the final state.
%%
%%  TODO> Add `ignore` response to be able to ignore unknown messages, for example.
%%
-callback handle_state(
        StateName   :: state_name(),
        Trigger     :: {event, Message} |
                       {sync, From, Message} |
                       {info, Message} |
                       {timer, Message} |
                       {Type, Message} |
                       {Type, From, Message} |
                       {Type, Source, Message} |
                       {Type, Source, From, Message} |
                       {exit, NextStateName} |
                       {entry, PrevStateName},
        StateData   :: state_data()
    ) ->
        {same_state, NewStateData} |
        {next_state, NextStateName, NewStateData} |
        {final_state, FinalStateName, NewStateData} |
        {reply_same, Reply, NewStateData} |
        {reply_next, Reply, NextStateName, NewStateData} |
        {reply_final, Reply, FinalStateName, NewStateData} |
        {ok, NewStateData}
    when
        Type    :: atom(),
        From    :: term(),
        Message :: term(),
        Source  :: event_src(),
        Reply   :: term(),
        NewStateData    :: state_data(),
        NextStateName   :: state_name(),
        PrevStateName   :: state_name(),
        FinalStateName  :: state_name().


%%
%%  Invoked when runtime process terminates. This is the case for both:
%%  the normal FSM termination and crashes. Parameters and response
%%  are defined in the same way, as it is done in the `gen_fsm`.
%%
-callback terminate(
        Reason      :: normal | shutdown | {shutdown,term()} | term(),
        StateName   :: state_name(),
        StateData   :: state_data()
    ) ->
        Term :: term().


%%
%%  This callback is used to handle code upgrades. Its use is similar to one,
%%  specified for the `gen_fsm`, except that its use is extended in this module.
%%  This callback will be invoked not only on hot code upgrades, but also in the cases,
%%  when the state can be changed to some new structure. In the case of state changes,
%%  the callback will be invoked with `state` as a first argument (and `Extra = undefined`).
%%
%%  The state changes will be indicated in the following cases:
%%
%%    * On process start or restart (when a persistent FSM becomes online).
%%    * On FSM resume (after being suspended).
%%
%%  This function will be invoked on hot code upgrade, as usual. In this case
%%  the function will be invoked as described in `gen_fsm`.
%%
%%  When upgrading the state data, runtime state index can be changed (or introduced).
%%  The new RuntimeField index in the StateData (assumes StateData to be a tuple)
%%  can be provided by returning it in result of this function. This is meaningfull
%%  for hot code upgrades, altrough useless for state upgrades on FSM (re)starts
%%  as `init/2` is called after this callback and will override the runtime field index.
%%
-callback code_change(
        OldVsn      :: (Vsn | {down, Vsn} | state),
        StateName   :: state_name(),
        StateData   :: state_data(),
        Extra       :: {advanced, Extra} | undefined
    ) ->
        {ok, NextStateName, NewStateData} |
        {ok, NextStateName, NewStateData, RuntimeField} |
        {error, Reason}
    when
        Vsn     :: term(),
        Extra   :: term(),
        NextStateName :: state_name(),
        NewStateData  :: state_data(),
        RuntimeField  :: integer(),
        Reason        :: term().


%%
%%  This function is used to format internal FSM state in some specific way.
%%  This is extended version of the corresponding function of the `gen_fsm`.
%%  This module extends that function by adding a case of `Opt = {external, ContentType}`.
%%  The function with this argument will be invoked when some external process asks
%%  for the external representation of the FSM state.
%%
%%  In the case of `Opt = {external, ContentType}`, the `State` parameter will contain
%%  a tuple with the StateName and StateData. The `format_status` callback will not be
%%  called from the FSM process in this case.
%%
%%  If the function will be called with `Opt = normal | terminate`, it will behave
%%  as described in `gen_fsm`. The `State` parameter will contain `[PDict, StateData]`.
%%
-callback format_status(
        Opt         :: normal | terminate | {external, ContentType},
        State       :: list() | {state, StateName, StateData}
    ) ->
        Status :: term()
    when
        ContentType :: term(),
        StateName   :: state_name(),
        StateData   :: state_data().



%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%  Creates new persistent FSM.
%%
%%  This function should be considered as a low-level API. The functions
%%  `send_create_event/*` and `sync_send_create_event/*` should be used
%%  in an ordinary case.
%%
%%  Parameters:
%%
%%  `Module`
%%  :   is a callback module implementing `eproc_fsm` behaviour.
%%  `Args`
%%  :   is passed to the `Module:init/3` function as the `Args` parameter. This
%%      is similar to the Args parameter in `gen_fsm` and other OTP behaviours.
%%  `Options`
%%  :   Proplist with options for the persistent FSM. The list can have
%%      common FSM options, FSM create options (listed bellow) as well as
%%      unknown options that can be used as a metadata for the FSM.
%%      Only the `store` option is supported from the Common FSM Options. Other
%%      common FSM options can be provided but will be ignored in this function.
%%
%%  On success, this function returns instance id of the newly created FSM.
%%  It can be used then to start the instance and to reference it.
%%
%%  FSM create options are the following:
%%
%%  `{group, group() | new}`
%%  :   Its a group ID to which the FSM should be assigned or atom `new`
%%      indicating that new group should be created for this FSM.
%%
%%  `{name, Name}`
%%  :   Name of the FSM. It uniquelly identifies the FSM.
%%      Name is valid for the entire FSM lifecycle, including
%%      the `completed` state.
%%
%%  `{start_spec, StartSpec :: start_spec()}`
%%  :   Tells, how the FSM should be started. Default is `{default, []}`.
%%      This option is used by `eproc_registry` therefore will be ignored,
%%      if the FSM will be used stand-alone, without the registry.
%%      Possible values for the StartSpec are:
%%
%%        * If StartSpec is in form `{default, StartOpts}` the FSM will
%%          be started using the default `eproc_fsm:start_link/2` function
%%          with StartOpts as a second parameter.
%%
%%        * If `{mfa, {Module, Function, Args}}` is specified as the StartSpec,
%%          the FSM will be started by calling the provided `Module:Function/?`
%%          with arguments `Args`. The Args list is preprocessed before passing
%%          it to the start function by replacing each occurence on `'$fsm_ref'`
%%          with the actual FSM reference (`{inst, InstId}`). It should be needed
%%          to call `eproc_fsm:start_link/2` later on.
%%
-spec create(
        Module  :: module(),
        Args    :: term(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref()} |
        {error, {already_created, fsm_ref()}}.

create(Module, Args, Options) ->
    {ok, CreateOpts, [], [], CommonOpts, UnknownOpts} = split_options(Options),
    case handle_create(Module, Args, lists:append(CreateOpts, CommonOpts), UnknownOpts) of
        {ok, InstId}                       -> {ok, {inst, InstId}};
        {error, {already_created, InstId}} -> {error, {already_created, {inst, InstId}}};
        {error, Reason}                    -> {error, Reason}
    end.


%%
%%  Start previously created (using `create/3`) `eproc_fsm` instance.
%%
%%  As part of initialization procedure, the FSM registers itself to the
%%  registry. Registration by InstId and Name is done synchronously or
%%  asynchronously (default), depending on the `start_sync` option.
%%
%%  This function should be considered as a low-level API. The functions
%%  `send_create_event/*` and `sync_send_create_event/*` should be used
%%  in an ordinary case.
%%
%%  Parameters:
%%
%%  `FsmName`
%%  :   Name to register the runtime FSM process with. This argument is similar to
%%      the FsmName in `gen_fsm`. Altrough this name is not related directly to the
%%      id and name of an instance (as provided when creating it) therefore FsmName
%%      can be different from them.
%%  `FsmRef`
%%  :   Reference of an previously created FSM. If instance id is going to be used
%%      as a reference, it can be obtained from the `create/3` function. Name or
%%      other types of references can also be used here.
%%  `Options'
%%  :   Runtime-level options. The options listed bellow are used by this
%%      FSM implementation and the rest are passed to the `gen_server:start_link/3`.
%%
%%  Options supprted by this function:
%%
%%  `{store, StoreRef}`
%%  :   a store to be used by the instance. If this option not provided, a store specified
%%      in the `eproc_core` application environment is used.
%%  `{registry, StoreRef}`
%%  :   a registry to be used by the instance. If this option not provided, a registry
%%      specified in the `eproc_core` application environment is used. `eproc_core` can
%%      cave no registry specified. In that case the registry will not be used.
%%  `{register, (none | id | name | both)}`
%%  :   specifies, what to register to the `eproc_registry` on startup.
%%      The registration is performed asynchronously and the id or name are those,
%%      loaded from the store during startup. These registration options are independent
%%      from the FsmName parameter. The FSM registers `id` and `name` (if name exists) by default,
%%      if registry exists. The startup will fail if this option is set to `id`, `name` or `both`,
%%      and the registry is not configured for the `eproc_core` application (app environment).
%%  `{start_sync, Sync :: boolean()}`
%%  :   starts FSM synchronously if `Sync = true` and asynchronously otherwise.
%%      Default is `false` (asynchronously). If FSM is started synchonously,
%%      FSM id and name will be registered within the EProc Registry before
%%      this function exits, if requested.
%%  `{limit_restarts, eproc_limits:limit_spec()}`
%%  :   Limits restarts of the FSM.
%%      Delays will be effective on process startup.
%%      The action `notify` will cause the FSM to suspend itself.
%%      The default is `undefined`. In such case the eproc_limits will not be used.
%%  `{limit_transitions, eproc_limits:limit_spec()}`
%%  :   Limits number of transition for the FSM.
%%      Delays will be effective on transition ends.
%%      The action `notify` will cause the FSM to suspend itself after processing the transition.
%%      The default is `undefined`. In such case the eproc_limits will not be used.
%%  `{limit_sent_msgs, [{all, eproc_limits:limit_spec()} | {dest, Destination, eproc_limits:limit_spec()}]}`
%%  :   Limits number of messages sent by the FSM.
%%      The counter will be updated in only on ends of transitions.
%%      As a consequence, the delays will be effective on transition ends.
%%      The action `notify` will cause the FSM to suspend itself after processing the transition.
%%      The default is `undefined`. In such case the eproc_limits will not be used.
%%  `{max_idle, TimeMS}`
%%  :   TODO: Suspend process if it is idle for to long.
%%      TODO: Support for hibernation should be added here.
%%
-spec start_link(
        FsmName     :: {local, atom()} | {global, term()} | {via, module(), term()},
        FsmRef      :: fsm_ref(),
        Options     :: proplist()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(FsmName, FsmRef, Options) ->
    {ok, StartOpts, ProcessOptions} = resolve_start_link_opts(Options),
    start_sync(gen_server:start_link(FsmName, ?MODULE, {FsmRef, StartOpts}, ProcessOptions), StartOpts).


%%
%%  Same as `start_link/3`, just without FsmName parameter.
%%
-spec start_link(
        FsmRef      :: fsm_ref(),
        Options     :: proplist()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(FsmRef, Options) ->
    {ok, StartOpts, ProcessOptions} = resolve_start_link_opts(Options),
    start_sync(gen_server:start_link(?MODULE, {FsmRef, StartOpts}, ProcessOptions), StartOpts).


%%
%%  Returns instance id, if invoked from an FSM process.
%%
-spec id() -> {ok, id()} | {error, not_fsm}.

id() ->
    case erlang:get('eproc_fsm$id') of
        undefined -> {error, not_fsm};
        Id        -> {ok, Id}
    end.


%%
%%  Returns instance group, if invoked from an FSM process.
%%
-spec group() -> {ok, group()} | {error, not_fsm}.

group() ->
    case erlang:get('eproc_fsm$group') of
        undefined -> {error, not_fsm};
        Group     -> {ok, Group}
    end.


%%
%%  Returns instance name, if invoked from an FSM process.
%%
-spec name() -> {ok, name()} | {error, not_fsm}.

name() ->
    case erlang:get('eproc_fsm$name') of
        undefined -> {error, not_fsm};
        Name      -> {ok, Name}
    end.


%%
%%  Checks, if a term is an FSM reference.
%%
-spec is_fsm_ref(fsm_ref() | term()) -> boolean().

is_fsm_ref({inst, _}) -> true;
is_fsm_ref({name, _}) -> true;
is_fsm_ref(_) -> false.


%%
%%  Checks, if a state is in specified scope.
%%
-spec is_state_in_scope(state_name(), state_scope()) -> boolean().

is_state_in_scope(State, Scope) when State =:= Scope; Scope =:= []; Scope =:= '_' ->
    true;

is_state_in_scope([BaseState | SubStates], [BaseScope | SubScopes]) when BaseState =:= BaseScope; BaseScope =:= '_' ->
    is_state_in_scope(SubStates, SubScopes);

is_state_in_scope([BaseState | SubStates], [BaseScope | SubScopes]) when element(1, BaseState) =:= BaseScope ->
    is_state_in_scope(SubStates, SubScopes);

is_state_in_scope([BaseState | _SubStates], [BaseScope | _SubScopes]) when is_tuple(BaseState), is_tuple(BaseScope) ->
    [StateName | StateRegions] = tuple_to_list(BaseState),
    [ScopeName | ScopeRegions] = tuple_to_list(BaseScope),
    RegionCheck = fun
        (_, false) -> false;
        ({St, Sc}, true) -> is_state_in_scope(St, Sc)
    end,
    NamesEqual = StateName =:= ScopeName,
    SizesEqual = tuple_size(BaseState) =:= tuple_size(BaseScope),
    case NamesEqual and SizesEqual of
        true -> lists:foldl(RegionCheck, true, lists:zip(StateRegions, ScopeRegions));
        false -> false
    end;

is_state_in_scope(_State, _Scope) ->
    false.


%%
%%  Checks if state name has valid structure.
%%
-spec is_state_valid(state_name()) -> boolean().

is_state_valid([]) ->
    true;

is_state_valid([BaseState | SubStates]) when is_atom(BaseState); is_binary(BaseState); is_integer(BaseState) ->
    is_state_valid(SubStates);

is_state_valid([BaseState]) when is_tuple(BaseState) ->
    [StateName | StateRegions] = tuple_to_list(BaseState),
    case is_state_valid([StateName]) of
        true ->
            RegionsCheckFun = fun
                (_, false) -> false;
                (S, true) -> is_state_valid(S)
            end,
            lists:foldl(RegionsCheckFun, true, StateRegions);
        false ->
            false
    end;

is_state_valid(_State) ->
    false.


%%
%%  Checks if the state name is valid for a transition target.
%%
%%  Comparing to the `is_state_valid/1`, the next state cannot be empty,
%%  and it can contain '_' in regions of an orthogonal state. The last
%%  situation is only allowed, if the FSM already was in the orthogonal
%%  state, that now has the underscores.
%%
-spec is_next_state_valid(StateName :: state_name(), PrevStateName :: state_name()) -> boolean().

is_next_state_valid(StateName, PrevStateName) ->
    case derive_next_state(StateName, PrevStateName) of
        {ok, _} -> true;
        {error, _} -> false
    end.


%%
%%  Equivalent to `is_next_state_valid(StateName, undefined | [])`.
%%  This function can be used instead of the mentioned, if orthogonal
%%  states are not used or used without wildcarding regions with '_'.
%%
-spec is_next_state_valid(NextStateName :: state_name()) -> boolean().

is_next_state_valid(NextStateName) ->
    is_next_state_valid(NextStateName, undefined).


%%
%%  Orthogonal states returned from the FSM callbacks can have unchanged
%%  regions marked with '_'. This function takes new state and the previous
%%  one and created the final state, as it should be after the transition.
%%
-spec derive_next_state(StateName :: state_name(), PrevStateName :: state_name())
    -> {ok, DerivedStateName :: state_name()} | {error, term()}.

derive_next_state([], _) ->
    {error, empty};

derive_next_state(StateName, PrevStateName) ->
    derive_next_sub_state(StateName, PrevStateName).


%%
%%  Internal function for `derive_next_state/2`.
%%
derive_next_sub_state([], _) ->
    {ok, []};

% If the state is simple, it should be atom, binary or integer.
derive_next_sub_state([Simple | SubStates], PrevStateName) when is_atom(Simple); is_binary(Simple); is_integer(Simple) ->
    PrevSubStates = case PrevStateName of
        [Simple | PSS] -> PSS;
        _              -> undefined
    end,
    case derive_next_sub_state(SubStates, PrevSubStates) of
        {ok, NewSubStates} -> {ok, [Simple | NewSubStates]};
        {error, Reason}    -> {error, Reason}
    end;

% If the state is orthogonal...
derive_next_sub_state([OrthState], PrevStateName) when is_tuple(OrthState) ->
    [StateName | StateRegions] = tuple_to_list(OrthState),
    case is_atom(StateName) of
        true ->
            RegionsResult = case PrevStateName of
                [PrevOrthState] when is_tuple(PrevOrthState),
                        element(1, PrevOrthState) =:= StateName,
                        tuple_size(PrevOrthState) =:= tuple_size(OrthState)
                        ->
                    % The FSM stays in the same FSM, so '_' can be used.
                    [StateName | PrevStateRegions] = tuple_to_list(PrevOrthState),
                    RegionsDeriveFun = fun
                        (_, {error, Reason}) ->
                            {error, Reason};
                        ({'_', PrevRegion}, {ok, Regions}) ->
                            case derive_next_state(PrevRegion, undefined) of
                                {error, Reason} -> {error, Reason};
                                {ok, NewRegion} -> {ok, [NewRegion | Regions]}
                            end;
                        ({Region, PrevRegion}, {ok, Regions}) ->
                            case derive_next_state(Region, PrevRegion) of
                                {error, Reason} -> {error, Reason};
                                {ok, NewRegion} -> {ok, [NewRegion | Regions]}
                            end
                    end,
                    lists:foldr(RegionsDeriveFun, {ok, []}, lists:zip(StateRegions, PrevStateRegions));
                _ ->
                    % The FSM came into the orthogonal state, all regions must be defined.
                    RegionsDeriveFun = fun
                        (_, {error, Reason}) ->
                            {error, Reason};
                        (Region, {ok, Regions}) ->
                            case derive_next_state(Region, undefined) of
                                {error, Reason} -> {error, Reason};
                                {ok, NewRegion} -> {ok, [NewRegion | Regions]}
                            end
                    end,
                    lists:foldr(RegionsDeriveFun, {ok, []}, StateRegions)
            end,
            case RegionsResult of
                {ok, NewRegions} -> {ok, [erlang:list_to_tuple([StateName | NewRegions])]};
                {error, RegionsReason} -> {error, RegionsReason}
            end;
        false ->
            {error, {bad_orthogonal, StateName}}
    end;

derive_next_sub_state(State, _) ->
    {error, {bad_state, State}}.


%%
%%  Creates new FSM, starts it and sends first message to it. The startup can be
%%  performed synchonously or asynchronously (default), depending on the `start_sync`
%%  option. It could be passed via `start_spec` option in this function.
%%  If the FSM is started synchonously, FSM instance id and name are registered
%%  before this function exits, if FSM was requested to register them.
%%  Nevertheless, the initial message is processed asynchronously.
%%
%%  This function should be used instead of calling `create/3`, `start_link/2-3`
%%  and first `send_event/2-3` in most cases, when using FSM with the `eproc_registry`.
%%  When the FSM used standalone, this function can be less usefull, because it
%%  depends on `eproc_registry`.
%%
%%  Parameters are the following:
%%
%%  `Module`
%%  :   is passed to the `create/3` function (see its description for more details).
%%  `Args`
%%  :   is passed to the `create/3` function (see its description for more details).
%%  `Event`
%%  :   stands for the initial event of the FSM, i.e. event that created the FSM.
%%      This event is used for invoking state transition callbacks for the transition
%%      from the initial ([]) state.
%%  `Options`
%%  :   can contain all options that are supported by the `create/3` and
%%      `send_event/2-3` functions. Options for `start_link/2-3` can be passed
%%      via `start_spec` option. Additionally, group is derived from the context
%%      and passed to the `create/3`, if it was not supplied explicitly.
%%
-spec send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref()} |
        {error, {already_created, fsm_ref()}} |
        {error, timeout} |
        {error, term()}.

send_create_event(Module, Args, Event, Options) ->
    case create_prepare_send(Module, Args, Options) of
        {ok, FsmRef, NewFsmRef, AllSendOpts} ->
            ok = send_event(NewFsmRef, Event, AllSendOpts),
            {ok, FsmRef};
        {error, Reason} ->
            {error, Reason}
    end.



%%
%%  Creates new FSM, starts it and sends first message synchonously to it. All the
%%  parameters and behaviour are similar to ones, described for `send_create_event/4`,
%%  except that first event is send synchonously, i.e. `sync_send_event/2-3` is used
%%  instead of `send_event/2-3`. Instance name and id will be registered before this
%%  function returns and therefore can be used safely.
%%
-spec sync_send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref(), Reply :: term()} |
        {error, {already_created, fsm_ref()}} |
        {error, timeout} |
        {error, term()}.

sync_send_create_event(Module, Args, Event, Options) ->
    case create_prepare_send(Module, Args, Options) of
        {ok, FsmRef, NewFsmRef, AllSendOpts} ->
            Reply = sync_send_event(NewFsmRef, Event, AllSendOpts),
            {ok, FsmRef, Reply};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Sends an event to the FSM asynchronously.
%%  This function returns `ok` immediatelly.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance.
%%      Standard OTP reference types can be used to access process, that was
%%      started with `FsmName` provided when invoking `start_link/3` or registered
%%      explicitly in a standard OTP process registry (like local, global or gproc).
%%      Additionally FSM reference in form `{inst, InstId}` or `{name, Name}` can
%%      be used if the FSM was started with the corresponding `register` option.
%%      PID (erlang process identifier) can be used to access the process in any case.
%%  `Event`
%%  :   Its an event to be sent to the FSM. It can be any term.
%%      This event is then passed to the `handle_state` callback.
%%  `Options`
%%  :   List of options, that can be specified when sending
%%      a message for the FSM. They are listed bellow.
%%
%%  Available options:
%%
%%  `{source, EventSrc}`
%%  :   This option can be used to specify event source (who is sending the event) explicitly.
%%      By default, this information is resolved from the context. The resolution is performed
%%      using the following sources (in order):
%%
%%       1. Explicitly specified by this option.
%%       2. Context of the sending process configured using `eproc_event_src` (uses process dictionary).
%%       3. The event is sent by an FSM instance. This case is also resolved from the process dictionary.
%%  `{type, MsgType :: binary() | atom() | function()}`
%%  :   User defined type of the event message. This type can be used to display
%%      message in more user-friendly, or to filter messages by it.
%%
%%  TODO: Options for metadata, event redelivery.
%%
-spec send_event(
        FsmRef  :: fsm_ref() | fsm_key() | otp_ref(),
        Event   :: term(),
        Options :: proplist()
    ) ->
        ok.

send_event(FsmRef, Event, Options) ->
    {ok, EventSrc} = resolve_event_src(Options),
    {ok, EventDst} = resolve_event_dst(FsmRef),
    {ok, EventTypeFun} = resolve_event_type_fun(Options),
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    SendFun = fun (SentMsgCId) ->
        CastMsg = {'eproc_fsm$send_event', Event, event, EventTypeFun, EventSrc, SentMsgCId},
        ok = gen_server:cast(ResolvedFsmRef, CastMsg)
    end,
    {ok, _SentMsgCId} = registered_send(EventSrc, EventDst, EventTypeFun, Event, SendFun),
    ok.


%%
%%  Simplified version of the `send_event/3`,
%%  equivalent to `send_event(FsmRef, Event, [])`.
%%
-spec send_event(
        FsmRef  :: fsm_ref() | fsm_key() | otp_ref(),
        Event   :: term()
    ) ->
        ok.

send_event(FsmRef, Event) ->
    send_event(FsmRef, Event, []).


%%
%%  Send event to itself. This function can only be used from within
%%  the FSM process. This function can be usefull to make checkpoints,
%%  where the process state should be recorded.
%%
%%  The event is delivered to the FSM with type `self`. If this function
%%  will be called with argument `next`, the trigger in the `handle_state/3`
%%  will be `{self, next}`.
%%
%%  This function returns `ok` immediatelly.
%%
%%  Parameters:
%%
%%  `Event`
%%  :   Its an event to be sent to the FSM. It can be any term.
%%      This event is then passed to the `handle_state` callback.
%%  `Options`
%%  :   List of options, that can be specified when sending
%%      a message for the FSM. They are listed bellow.
%%
%%  Available options:
%%
%%  `{type, MsgType :: binary() | atom() | function()}`
%%  :   User defined type of the event message. This type can be used to display
%%      message in more user-friendly, or to filter messages by it.
%%
-spec self_send_event(
        Event   :: term(),
        Options :: proplist()
    ) ->
        ok |
        {error, Reason :: not_fsm | term()}.

self_send_event(Event, Options) ->
    case id() of
        {ok, InstId} ->
            SelfRef = {inst, InstId},
            SelfPid = self(),
            {ok, EventTypeFun} = resolve_event_type_fun(Options),
            SendFun = fun (SentMsgCId) ->
                % TODO: Why EventTypeFun is fun? It can cause problems in a cluster.
                CastMsg = {'eproc_fsm$send_event', Event, self, EventTypeFun, SelfRef, SentMsgCId},
                ok = gen_server:cast(SelfPid, CastMsg)
            end,
            {ok, _SentMsgCId} = registered_send(SelfRef, SelfRef, EventTypeFun, Event, SendFun),
            ok;
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Simplified version of the `self_send_event/2`,
%%  equivalent to `self_send_event(Event, [])`.
%%
-spec self_send_event(
        Event   :: term()
    ) ->
        ok.

self_send_event(Event) ->
    self_send_event(Event, []).


%%
%%  Sends an event to the FSM synchronously. The function returns term, provided
%%  by the FSM callback module, similarly to the corresponding function in `gen_fsm`.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance.
%%      See `send_event/3` for more details.
%%  `Event`
%%  :   Its an event to be sent to the FSM. It can be any term.
%%      This event is then passed to the `handle_state` callback.
%%  `Options`
%%  :   List of options, that can be specified when sending a message
%%      for the FSM. All options supported by `send_event/3` are also
%%      supported here.
%%
%%  The following options are valid here (additionally to `send_event/3`):
%%
%%  `{type, MsgType :: binary() | atom() | function()}`
%%  :   User defined type of the event message. This type can be used to display
%%      message in more user-friendly, or to filter messages by it.
%%  `{timeout, Timeout}`
%%  :   Maximal time in milliseconds for the synchronous call.
%%      5000 (5 seconds) is the default.
%%
-spec sync_send_event(
        FsmRef  :: fsm_ref() | fsm_key() | otp_ref(),
        Event   :: term(),
        Options :: proplist()
    ) ->
        Reply :: term().

sync_send_event(FsmRef, Event, Options) ->
    {ok, EventSrc}     = resolve_event_src(Options),
    {ok, EventDst}     = resolve_event_dst(FsmRef),
    {ok, EventTypeFun} = resolve_event_type_fun(Options),
    {ok, Timeout}      = resolve_timeout(Options),
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    SendFun = fun (SentMsgCId) ->
        CallMsg = {'eproc_fsm$sync_send_event', Event, EventTypeFun, EventSrc, SentMsgCId},
        {ok, InstId, RespMsgCId, RespMsg} = gen_server:call(ResolvedFsmRef, CallMsg, Timeout),
        {ok, RespMsg, RespMsgCId, {inst, InstId}}
    end,
    {ok, _SentMsgCId, _RespMsgCId, RespMsg} = registered_sync_send(EventSrc, EventDst, EventTypeFun, Event, SendFun),
    RespMsg.


%%
%%  Simplified version of the `sync_send_event/3`,
%%  equivalent to `sync_send_event(FsmRef, Event, [])`.
%%
-spec sync_send_event(
        FsmRef  :: fsm_ref() | fsm_key() | otp_ref(),
        Event   :: term()
    ) ->
        Reply :: term().

sync_send_event(FsmRef, Event) ->
    sync_send_event(FsmRef, Event, []).


%%
%%  Kills existing FSM instance. The FSM can be either online or offline.
%%  If FSM is online, it will be stopped. In any case, the FSM will be marked
%%  as killed. This function also returns `ok` if the FSM was already terminated.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance. The reference must be either
%%      `{inst, _}` or `{name, _}`. Erlang process ids or names are not
%%      supported here. See `send_event/3` for more details.
%%  `Options`
%%  :   Any of the Common FSM Options can be provided here.
%%      Only `store`, `registry` and `user` options will be used here
%%      and other options will be ignored.
%%
%%  This function depends on `eproc_registry`.
%%
-spec kill(
        FsmRef  :: fsm_ref() | otp_ref(),
        Options :: list()
    ) ->
        {ok, ResolvedFsmRef :: fsm_ref()} |
        {error, bad_ref} |
        {error, Reason :: term()}.

kill(FsmRef, Options) ->
    case is_fsm_ref(FsmRef) of
        false ->
            {error, bad_ref};
        true ->
            Store = resolve_store(Options),
            UserAction = resolve_user_action(Options),
            case eproc_store:set_instance_killed(Store, FsmRef, UserAction) of
                {ok, InstId} ->
                    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
                    ok = gen_server:cast(ResolvedFsmRef, {'eproc_fsm$kill'}),
                    {ok, {inst, InstId}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.


%%
%%  Suspends existing FSM instance. The FSM can be either online or offline.
%%  If FSM is online, it will be stopped. In any case, the FSM will be marked
%%  as suspended. This function also returns `ok` if the FSM was already
%%  suspended, and error if the FSM is already terminated.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance. The reference must be either
%%      `{inst, _}` or `{name, _}`. Erlang process ids or names are not
%%      supported here. See `send_event/3` for more details.
%%  `Options`
%%  :   Any of the Common FSM Options can be provided here.
%%      Only `store`, `registry` and `user` options will be used here
%%      and other options will be ignored.
%%
%%  This function depends on `eproc_registry`.
%%
-spec suspend(
        FsmRef  :: fsm_ref(),
        Options :: list()
    ) ->
        {ok, ResolvedFsmRef :: fsm_ref()} |
        {error, bad_ref} |
        {error, Reason :: term()}.

suspend(FsmRef, Options) ->
    case is_fsm_ref(FsmRef) of
        false ->
            {error, bad_ref};
        true ->
            Store = resolve_store(Options),
            UserAction = resolve_user_action(Options),
            case eproc_store:set_instance_suspended(Store, FsmRef, UserAction) of
                {ok, InstId} ->
                    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
                    ok = gen_server:cast(ResolvedFsmRef, {'eproc_fsm$suspend'}),
                    {ok, {inst, InstId}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.


%%
%%  Suspends the current FSM. This function can only be called
%%  by the FSM callback module, in the `handle_state/3` function.
%%
%%  This function does not suspend the FSM immediatelly. It rather
%%  orders the suspending on the end of the current transition.
%%
%%  If this function is called in the beginning of the transition,
%%  the next callbacks in the transition (`entry` and `exit`)
%%  will be called as usual.
%%
-spec suspend(Reason :: term()) -> ok.

suspend(Reason) ->
    case erlang:put('eproc_fsm$suspend', {true, Reason}) of
        false -> ok;
        {true, _OldReason} -> ok
    end.


%%
%%  Resumes previously suspended FSM instance. If the FSM is not suspended
%%  (still suspending or just running), an error will be rised.
%%  While performing resume, the FSM will be marked as running
%%  and opionally started in the registry (made online).
%%  The instance startup is performed synchronously.
%%  It is an error to resume already terminated process.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance. The reference must be either
%%      `{inst, _}` or `{name, _}`. Erlang process ids or names are not
%%      supported here. See `send_event/3` for more details.
%%  `Options`
%%  :   Any of the Common FSM Options can be provided here.
%%      Only `store`, `registry` and `user` options will be used
%%      here, other options will be ignored. Options, specific to
%%      this function are listed bellow.
%%
%%  Options, specific to this function:
%%
%%  `{state, unchanged | retry_last | {set, NewStateName, NewStateData, ResumeScript}}`
%%  :   When resuming the FSM, its internal state can be changed.
%%      This option specifies, what state to use in the resumed FSM.
%%
%%        * The option `unchanged` indicates to use FSM's original state,
%%          as it was at the moment when the FSM was interrupted.
%%        * The option `retry_last` indicates to use state of the last resume
%%          attempt or the original state, if there was no resume attempts.
%%          This is the default option.
%%        * An the option `{set, NewStateName, NewStateData, ResumeScript}` indicates
%%          to use new state, as provided explicitly. All of the `NewStateName`,
%%          `NewStateData`, `ResumeScript` can be `undefined`, which means to leave
%%          the corresponding field unchanged (or script being empty).
%%
%%  `{start, (no | yes | start_spec())}`
%%  :   indicates, if and how the FSM should be started, after marking it as resuming.
%%      The automatic startup implies dependency on EProc Registry in this function.
%%
%%        * The option 'no' indicates, that the FSM should not be started automatically.
%%          In this case, the application can start the FSM manually afterward.
%%          EProc registry is not used in this case.
%%        * If the option `yes` is provided, the EProc Registry will be used to start
%%          the FSM with start specification provided when creating the FSM.
%%          The is the default case.
%%        * Third option is to provide the start specification explicitly.
%%          In this case the registry will be used, altrough the start specification
%%          provided explicitly will be used instead of the specification provided
%%          when creating the FSM.
%%
%%  `{fsm_ref, fsm_ref()}`
%%  :   This option can be used to provide FSM reference. This is only meaningfull,
%%      if the `FsmRef` parameter is `otp_ref()`. Altrough FSM cannot be started with
%%      `FsmRef :: otp_ref()`, one can use this option with standalone FSM, to resume
%%      it not using EProc Registry. If this option is provided, the FsmRef parameter
%%      will only be used to check if the FSM is online or not. All other actions will
%%      be performed using the reference provided by this option.
%%
-spec resume(
        FsmRef      :: fsm_ref() | otp_ref(),
        Options     :: list()
    ) ->
        {ok, ResolvedFsmRef :: fsm_ref()} |
        {error, bad_ref} |
        {error, running} |
        {error, Reason :: term()}.

resume(FsmRef, Options) ->
    FsmRefInStore = proplists:get_value(fsm_ref, Options, FsmRef),
    case {is_fsm_ref(FsmRefInStore), is_online(FsmRef)} of
        {false, _} ->
            {error, bad_ref};
        {true, true} ->
            {error, running};
        {true, false} ->
            Store = resolve_store(Options),
            UserAction = resolve_user_action(Options),
            StateAction = proplists:get_value(state, Options, retry_last),
            StartAction = proplists:get_value(start, Options, yes),
            case eproc_store:set_instance_resuming(Store, FsmRefInStore, StateAction, UserAction) of
                {ok, InstId, StoredStartSpec} ->
                    case StartAction of
                        no ->
                            {ok, {inst, InstId}};
                        _ ->
                            StartSpec = case StartAction of
                                yes -> StoredStartSpec;
                                ProvidedStartSpec when is_tuple(ProvidedStartSpec) -> ProvidedStartSpec
                            end,
                            Registry = resolve_registry(Options),
                            {ok, ResolvedFsmRef} = eproc_registry:make_new_fsm_ref(Registry, {inst, InstId}, StartSpec),
                            try gen_server:call(ResolvedFsmRef, {'eproc_fsm$is_online'}) of
                                true -> {ok, {inst, InstId}}
                            catch
                                C:E ->
                                    lager:error("FSM resume failed with reason ~p:~p at ~p", [C, E, erlang:get_stacktrace()]),
                                    {error, resume_failed}
                            end
                    end;
                {error, running} ->
                    {error, running};
                {error, Reason} ->
                    {error, Reason}
            end
    end.


%%
%%  Updates FSM internal state explicitly. This funcion should only be used
%%  as a tool for an administrator (in a script, or from some GUI) to fix
%%  broken processes. This function suspends the FSM and then tries to resume
%%  it with new state. Additionally, it waits till the FSM will be terminated
%%  before attempting to resume it. This function will work as resume/2 for
%%  already suspended processes with `{state, {set, NewStateName, NewStateData, UpdateScript}}` option.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance. The reference must be either
%%      `{inst, _}` or `{name, _}`. Erlang process ids or names are not
%%      supported here. See `send_event/3` for more details.
%%  `NewStateName`
%%  :   New state name, or undefined.
%%  `NewStateData`
%%  :   New state data, or undefined.
%%  `UpdateScript`
%%  :   Script, to be executed when resuming the FSM.
%%  `Options`
%%  :   Any of the Common FSM Options can be provided here as well
%%      as all options, supported by `suspend/2` and `resume/2` functions.
%%      Only `store`, `registry` and `user` common options will be used
%%      here, other options will be ignored. Options, specific to
%%      this function are listed bellow.
%%
%%  Options, specific to this function:
%%
%%  `{timeout, Timeout}`
%%  :   Stands for a timeout in ms to wait for FSM to suspend.
%%
-spec update(
        FsmRef          :: fsm_ref(),
        NewStateName    :: state_name() | undefined,
        NewStateData    :: state_data() | undefined,
        UpdateScript    :: script() | undefined,
        Options         :: list()
    ) ->
        {ok, ResolvedFsmRef :: fsm_ref()} |
        {error, Reason :: term()}.

update(FsmRef, NewStateName, NewStateData, UpdateScript, Options) ->
    Registry = proplists:get_value(registry, Options, undefined),
    Timeout  = proplists:get_value(timeout,  Options, 5000),
    FsmPID = eproc_registry:whereis_fsm(Registry, FsmRef),
    MonitorRef = case FsmPID of
        undefined -> undefined;
        _         -> erlang:monitor(process, FsmPID)
    end,
    case suspend(FsmRef, Options) of
        {ok, SuspendedFsmRef} ->
            WaitResult = case MonitorRef of
                undefined ->
                    ok;
                _ ->
                    receive
                        {'DOWN', MonitorRef, process, FsmPID, _Info} ->
                            ok
                    after Timeout ->
                        lager:error("Timeout while waiting for FSM ~p to suspend.", [FsmRef]),
                        {error, timeout}
                    end
            end,
            case WaitResult of
                ok ->
                    UpdateOpt = {state, {set, NewStateName, NewStateData, UpdateScript}},
                    resume(SuspendedFsmRef, [UpdateOpt | Options]);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Checks if process is online. This function makes a synchronous call to
%%  the FSM process, so it can be used for sinchronizing with the FSM.
%%  E.g. for waiting for asynchronous initialization to complete.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   References particular FSM instance.
%%      See `send_event/3` for more details.
%%  `Options`
%%  :   Any of the Common FSM Options can be provided here.
%%      Only the `registry` option will be used, other will be ignored.
%%
-spec is_online(
        FsmRef  :: fsm_ref() | otp_ref(),
        Options :: list()
    ) ->
        boolean().

is_online(FsmRef, Options) ->
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    case catch gen_server:call(ResolvedFsmRef, {'eproc_fsm$is_online'}) of
        true                  -> true;
        {'EXIT', {normal, _}} -> false;
        {'EXIT', {noproc, _}} -> false
    end.


%%
%%  Equivalent to `is_online(FsmRef, [])`.
%%
-spec is_online(
        FsmRef  :: fsm_ref() | otp_ref()
    ) ->
        boolean().

is_online(FsmRef) ->
    is_online(FsmRef, []).


%%
%%  To be used by the process implementation to sent response to a synchronous
%%  request before the `handle_state/3` function completes.
%%
%%  Parameters:
%%
%%  `To`
%%  :   A recipient, who should receive the reply. The parameter `From` from
%%      the `handle_state` `{sync, From, Message}`should be passed here.
%%  `Reply`
%%  :   The reply message.
%%
%%  The function returns `ok` on success.
%%
-spec reply(
        To    :: term(),
        Reply :: state_event()
    ) ->
        ok |
        {error, Reason :: term()}.

reply({InstId, TrnNr, ReplyFun}, Reply) ->
    ReplyMsgCId = ?MSGCID_REPLY(InstId, TrnNr),
    noreply = erlang:put('eproc_fsm$reply', {reply, ReplyMsgCId, Reply}),
    ReplyFun(InstId, ReplyMsgCId, Reply).


%%
%%  Register an outgoing message, sent by the FSM. This function is used by
%%  modules sending outgoing messages from the FSM, like connectors.
%%
%%  See also: `registered_send` and `registered_sync_send`.
%%
-spec register_sent_msg(
        Src         :: event_src(),
        Dst         :: event_src(),
        SentMsgCId  :: msg_cid() | undefined,
        SentMsgType :: binary(),
        SentMsg     :: term(),
        Timestamp   :: timestamp()
    ) ->
        {ok, msg_cid()} |
        {error, not_fsm}.

%%  Event between FSMs (if Dst = {inst, _}) or FSM sends external event.
%%  The sending FSM is responsible for storing the message.
register_sent_msg({inst, SrcInstId}, Dst, SentMsgCId, SentMsgType, SentMsg, Timestamp) ->
    MsgRegs = #msg_regs{
        inst_id     = SrcInstId,
        trn_nr      = TrnNr,
        next_msg_nr = NextMsgNr,
        registered  = Registered
    } = erlang:get('eproc_fsm$msg_regs'),
    {NewNextMsgNr, NewMsgCId} = case SentMsgCId of
        undefined             -> {NextMsgNr + 1, ?MSGCID_SENT(SrcInstId, TrnNr, NextMsgNr)};
        ?MSGCID_RECV(I, T, M) -> {NextMsgNr,     ?MSGCID_SENT(I,         T,     M        )}
    end,
    NewMsgReg = #msg_reg{
        dst = Dst,
        sent_cid = NewMsgCId,
        sent_msg = SentMsg,
        sent_type = SentMsgType,
        sent_time = Timestamp
    },
    NewRegistered = [NewMsgReg | Registered],
    erlang:put('eproc_fsm$msg_regs', MsgRegs#msg_regs{next_msg_nr = NewNextMsgNr, registered = NewRegistered}),
    {ok, NewMsgCId};

%%  FSM received an external event (if Dst = {inst, _}) or the event is not related to FSMs.
%%  The receiving FSM is responsible for storing the message.
register_sent_msg(_Src, _Dst, _SentMsgCId, _SentMsgType, _SentMsg, _Timestamp) ->
    {error, not_fsm}.


%%
%%  Registers response message of the outgoing call made by FSM.
%%  This function should be called only if corresponding call to
%%  `register_sent_msg` returned `{ok, SentMsgCId}`.
%%
%%  See also: `registered_sync_send`.
%%
-spec register_resp_msg(
        Src         :: event_src(),
        Dst         :: event_src(),
        SentMsgCId  :: msg_cid(),
        RespMsgCId  :: msg_cid() | undefined,
        RespMsgType :: binary(),
        RespMsg     :: term(),
        Timestamp   :: timestamp()
    ) ->
        {ok, msg_cid()} |
        {error, no_sent}.

register_resp_msg({inst, SrcInstId}, Dst, SentMsgCId, RespMsgCId, RespMsgType, RespMsg, Timestamp) ->
    MsgRegs = #msg_regs{
        inst_id     = SrcInstId,
        trn_nr      = TrnNr,
        next_msg_nr = NextMsgNr,
        registered  = Registered
    } = erlang:get('eproc_fsm$msg_regs'),
    case lists:keyfind(SentMsgCId, #msg_reg.sent_cid, Registered) of
        false ->
            {error, no_sent};
        MsgReg ->
            {NewNextMsgNr, NewMsgCId} = case RespMsgCId of
                undefined             -> {NextMsgNr + 1, ?MSGCID_RECV(SrcInstId, TrnNr, NextMsgNr)};
                ?MSGCID_SENT(I, T, M) -> {NextMsgNr,     ?MSGCID_RECV(I,         T,     M        )}
            end,
            NewMsgReg = MsgReg#msg_reg{
                dst = Dst,
                resp_cid = NewMsgCId,
                resp_msg = RespMsg,
                resp_type = RespMsgType,
                resp_time = Timestamp
            },
            NewRegistered = lists:keyreplace(SentMsgCId, #msg_reg.sent_cid, Registered, NewMsgReg),
            erlang:put('eproc_fsm$msg_regs', MsgRegs#msg_regs{next_msg_nr = NewNextMsgNr, registered = NewRegistered}),
            {ok, NewMsgCId}
    end.


%%
%%  Helper function for registering asynchronous outgoing message.
%%  This function can be used instead of `register_sent_msg`.
%%
registered_send(EventSrc, EventDst, EventTypeFun, Event, SendFun) ->
    EventType = EventTypeFun(event, Event),
    case register_sent_msg(EventSrc, EventDst, undefined, EventType, Event, os:timestamp()) of
        {ok, SentMsgCId} ->
            ok = SendFun(SentMsgCId),
            {ok, SentMsgCId};
        {error, not_fsm} ->
            ok = SendFun(undefined),
            {ok, undefined}
    end.


%%
%%  Helper function for registering synchronous outgoing messages.
%%  This function can be used instead of `register_sent_msg` and `register_resp_msg`.
%%
registered_sync_send(EventSrc, EventDst, EventTypeFun, Event, SendFun) ->
    EventType = EventTypeFun(sync, Event),
    case register_sent_msg(EventSrc, EventDst, undefined, EventType, Event, os:timestamp()) of
        {ok, SentMsgCId} ->
            {ok, OurRespMsgCId} = case SendFun(SentMsgCId) of
                {ok, RespMsg, RespMsgCId, UpdatedDst} ->
                    RespTime = os:timestamp(),
                    RespMsgType = EventTypeFun(resp, RespMsg),
                    register_resp_msg(EventSrc, UpdatedDst, SentMsgCId, RespMsgCId, RespMsgType, RespMsg, RespTime);
                {ok, RespMsg} ->
                    RespTime = os:timestamp(),
                    RespMsgType = EventTypeFun(resp, RespMsg),
                    register_resp_msg(EventSrc, EventDst, SentMsgCId, undefined, RespMsgType, RespMsg, RespTime)
            end,
            {ok, SentMsgCId, OurRespMsgCId, RespMsg};
        {error, not_fsm} ->
            case SendFun(undefined) of
                {ok, RespMsg, _RespMsgCId, _UpdatedDst} -> ok;
                {ok, RespMsg} -> ok
            end,
            {ok, undefined, undefined, RespMsg}
    end.


%%
%%  Converts FSM start specification to a list of arguments
%%  for a `eproc_fsm:start_link/2-3` function or an MFA.
%%
-spec resolve_start_spec(
        FsmRef      :: fsm_ref(),
        StartSpec   :: start_spec()
    ) ->
        {start_link_args, Args :: list()} |
        {start_link_mfa, {Module :: module(), Function :: atom(), Args :: list()}}.

resolve_start_spec(FsmRef, {default, StartOpts}) when is_list(StartOpts) ->
    {start_link_args, [FsmRef, StartOpts]};

resolve_start_spec(FsmRef, {mfa, {Module, Function, Args}}) when is_atom(Module), is_atom(Function), is_list(Args) ->
    FsmRefMapFun = fun
        ('$fsm_ref') -> FsmRef;
        (Other) -> Other
    end,
    ResolvedArgs = lists:map(FsmRefMapFun, Args),
    {start_link_mfa, {Module, Function, ResolvedArgs}}.



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({FsmRef, StartOpts}) ->
    {LimMsgAll, LimMsgDst} = case proplists:get_value(limit_sent_msgs, StartOpts, undefined) of
        undefined ->
            {undefined, undefined};
        LimMsg ->
            {
                case [ L      || {all, L}     <- LimMsg ] of [] -> undefined; [L] -> L  end,
                case [ {D, L} || {dest, D, L} <- LimMsg ] of [] -> undefined; DL  -> DL end
            }
    end,
    State = #state{
        store       = resolve_store(StartOpts),
        registry    = resolve_registry(StartOpts),
        lim_res     = proplists:get_value(limit_restarts,    StartOpts, undefined),
        lim_trn     = proplists:get_value(limit_transitions, StartOpts, undefined),
        lim_msg_all = LimMsgAll,
        lim_msg_dst = LimMsgDst
    },
    self() ! {'eproc_fsm$start', FsmRef, StartOpts},
    {ok, State}.


%%
%%  Syncronous calls.
%%
handle_call({'eproc_fsm$is_online'}, _From, State) ->
    {reply, true, State};

handle_call({'eproc_fsm$sync_send_event', Event, EventTypeFun, EventSrc, MsgCId}, From, State) ->
    Trigger = #trigger_spec{
        type = sync,
        source = EventSrc,
        message = Event,
        msg_cid = MsgCId,
        msg_type_fun = EventTypeFun,
        sync = true,
        reply_fun = fun (IID, RMsgCId, RMsg) -> gen_server:reply(From, {ok, IID, RMsgCId, RMsg}), ok end,
        src_arg = false
    },
    TransitionFun = fun (Trg, TNr, St) -> perform_event_transition(Trg, TNr, [], St) end,
    case perform_transition(Trigger, TransitionFun, State) of
        {cont, NewState} -> {noreply, NewState};
        {stop, NewState} -> shutdown(NewState);
        {error, Reason}  -> {stop, {error, Reason}, State}
    end.


%%
%%  Asynchronous messages.
%%
handle_cast({'eproc_fsm$send_event', Event, EventType, EventTypeFun, EventSrc, MsgCId}, State) ->
    Trigger = #trigger_spec{
        type = EventType,
        source = EventSrc,
        message = Event,
        msg_cid = MsgCId,
        msg_type_fun = EventTypeFun,
        sync = false,
        reply_fun = undefined,
        src_arg = false
    },
    TransitionFun = fun (Trg, TNr, St) -> perform_event_transition(Trg, TNr, [], St) end,
    case perform_transition(Trigger, TransitionFun, State) of
        {cont, NewState} -> {noreply, NewState};
        {stop, NewState} -> shutdown(NewState);
        {error, Reason}  -> {stop, {error, Reason}, State}
    end;

handle_cast({'eproc_fsm$kill'}, State = #state{inst_id = InstId}) ->
    lager:notice("FSM id=~p killed.", [InstId]),
    shutdown(State);

handle_cast({'eproc_fsm$suspend'}, State = #state{inst_id = InstId}) ->
    lager:notice("FSM id=~p suspended.", [InstId]),
    shutdown(State).


%%
%%  Asynchronous FSM initialization.
%%
handle_info({'eproc_fsm$start', FsmRef, StartOpts}, State) ->
    case handle_start(FsmRef, StartOpts, State) of
        {online, NewState} -> {noreply, NewState};
        {offline, InstId}  -> shutdown(State#state{inst_id = InstId})
    end;

%%
%%  Handles FSM attribute events.
%%
handle_info(Event, State = #state{inst_id = InstId, attrs = Attrs}) ->
    case eproc_fsm_attr:event(InstId, Event, Attrs) of
        {handled, NewAttrs} ->
            {noreply, State#state{attrs = NewAttrs}};
        {trigger, NewAttrs, Trigger, AttrAction} ->
            TransitionFun = fun (Trg, TNr, St) -> perform_event_transition(Trg, TNr, [AttrAction], St) end,
            case perform_transition(Trigger, TransitionFun, State#state{attrs = NewAttrs}) of
                {cont, NewState} -> {noreply, NewState};
                {stop, NewState} -> shutdown(NewState);
                {error, Reason}  -> {stop, {error, Reason}, State#state{attrs = NewAttrs}}
            end;
        unknown ->
            Trigger = #trigger_spec{
                type = info,
                source = undefined,
                message = Event,
                msg_cid = undefined,
                msg_type_fun = fun resolve_event_type/2,
                sync = false,
                reply_fun = undefined,
                src_arg = false
            },
            TransitionFun = fun (Trg, TNr, St) -> perform_event_transition(Trg, TNr, [], St) end,
            case perform_transition(Trigger, TransitionFun, State) of
                {cont, NewState} -> {noreply, NewState};
                {stop, NewState} -> shutdown(NewState);
                {error, Reason}  -> {stop, {error, Reason}, State}
            end
    end.


%%
%%  Invoked, when the FSM terminates.
%%
terminate(_Reason, _State) ->
    ok. % TODO: Call CB:terminate


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.    % TODO: Call CB:code_change.


% TODO: Call format_status from somewhere.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Shutdown the FSM.
%%
shutdown(State) ->
    ok = limits_cleanup(State),
    {stop, normal, State}.


%%
%%  Extracts timeout from the options.
%%
resolve_timeout(Options) ->
    Timeout = proplists:get_value(timeout, Options, ?DEFAULT_TIMEOUT),
    {ok, Timeout}.


%%
%%  Classifies options to start options and unknown options.
%%
resolve_start_link_opts(Options) ->
    {ok, [], StartOpts, [], CommonOpts, UnknownOpts} = split_options(Options),
    {ok, lists:append(StartOpts, CommonOpts), UnknownOpts}.


%%
%%  Resolves group id and adds it to the options, if it was missing.
%%  Group is taken from the context of the calling process
%%  if not provided in the options explicitly. If the calling
%%  process is not FSM, new group will be created.
%%
resolve_append_group(CreateOpts) ->
    case proplists:is_defined(group, CreateOpts) of
        true -> CreateOpts;
        false ->
            case group() of
                {ok, Group} -> [{group, Group} | CreateOpts];
                {error, not_fsm} -> [{group, new} | CreateOpts]
            end
    end.


%%
%%  Gets start specs from the FSM create options.
%%
resolve_start_spec(CreateOpts) ->
    StartSpec = proplists:get_value(start_spec, CreateOpts, {default, []}),
    {ok, StartSpec}.


%%
%%  Returns either instance id or undefined, if the current process
%%  is not `eproc_fsm` process.
%%
resolve_event_src(SendOptions) ->
    case proplists:lookup(source, SendOptions) of
        none ->
            case {eproc_event_src:source(), id()} of
                {undefined, {ok, InstId}}     -> {ok, {inst, InstId}};
                {undefined, {error, not_fsm}} -> {ok, undefined};
                {{_, _} = EventSrc,  _}       -> {ok, EventSrc}
            end;
        {source, undefined}->
            {ok, undefined};
        {source, {_, _} = EventSrc}->
            {ok, EventSrc}
    end.


%%
%%  Returns destination FSM reference, used to pass it to `regisrer_out_msg/3`.
%%
resolve_event_dst({inst, InstId}) ->
    {ok, {inst, InstId}};

resolve_event_dst(_) ->
    {ok, {inst, undefined}}.


%%
%%  Returns a fun, producing message types.
%%
resolve_event_type_fun(SendOptions) ->
    case proplists:lookup(type, SendOptions) of
        none ->
            {ok, fun resolve_event_type/2};
        {type, Const} when is_binary(Const); is_atom(Const) ->
            {ok, fun (EventRole, Event) ->
                resolve_event_type_const(EventRole, Const, Event)
            end};
        {type, Fun} when is_function(Fun, 2) ->
            {ok, Fun}
    end.


%%
%%  Default implementation for deriving event type from the event message.
%%
resolve_event_type(_EventRole, Atom) when is_atom(Atom) ->
    erlang:atom_to_binary(Atom, utf8);

resolve_event_type(_EventRole, Binary) when is_binary(Binary) ->
    Binary;

resolve_event_type(EventRole, TaggedTuple) when is_tuple(TaggedTuple), is_atom(element(1, TaggedTuple)) ->
    resolve_event_type(EventRole, element(1, TaggedTuple));

resolve_event_type(_EventRole, Term) ->
    IoList = io_lib:format("~W", [Term, 3]),
    erlang:iolist_to_binary(IoList).


%%
%%  This function uses supplied type for request messages and
%%  the default implementation for responses and all other.
%%
resolve_event_type_const(EventRole, EventTypeConst, _Event) when EventRole =:= event; EventRole =:= sync ->
    if
        is_binary(EventTypeConst) ->
            EventTypeConst;
        is_atom(EventTypeConst) ->
            erlang:atom_to_binary(EventTypeConst, utf8)
    end;

resolve_event_type_const(EventRole, _EventTypeConst, Event) ->
    resolve_event_type(EventRole, Event).


%%
%%  Resolves instance reference.
%%
resolve_fsm_ref(FsmRef, Options) ->
    MakeFsmRefFun = fun (Ref) ->
        Registry = resolve_registry(Options),
        {ok, _ResolvedFsmRef} = eproc_registry:make_fsm_ref(Registry, Ref)
    end,
    LookupFun = fun (LookupKey, LookupOpts) ->
        case eproc_router:lookup(LookupKey, LookupOpts) of
            {ok, [InstId]}  -> MakeFsmRefFun({inst, InstId});
            {ok, []}        -> {error, not_found};
            {ok, _}         -> {error, multiple};
            {error, Reason} -> {error, Reason}
        end
    end,
    case is_fsm_ref(FsmRef) of
        true ->
            MakeFsmRefFun(FsmRef);
        false ->
            case FsmRef of
                {key, Key}       -> LookupFun(Key, []);
                {key, Key, Opts} -> LookupFun(Key, Opts);
                _                -> {ok, FsmRef}
            end
    end.


%%
%%  Resolve store.
%%
resolve_store(StartOpts) ->
    case proplists:get_value(store, StartOpts) of
        undefined ->
            {ok, Store} = eproc_store:ref(),
            Store;
        Store ->
            Store
    end.


%%
%%  Resolve registry, if needed.
%%
resolve_registry(StartOpts) ->
    case {proplists:get_value(register, StartOpts), proplists:get_value(registry, StartOpts)} of
        {none, undefined} ->
            undefined;
        {undefined, undefined} ->
            undefined;
        {_, undefined} ->
            case eproc_registry:ref() of
                {ok, Registry} ->
                    Registry;
                undefined ->
                    undefined
            end;
        {_, Registry} ->
            Registry
    end.


%%
%%  Creates user action from the supplied options.
%%
resolve_user_action(CommonOpts) ->
    {User, Comment} = case proplists:get_value(user, CommonOpts) of
        {U = #user{}, C} when is_binary(C) ->
            {U, C};
        {U, C} when is_binary(U), is_binary(C) ->
            {#user{uid = U}, C};
        U = #user{} ->
            {U, undefined};
        U when is_binary(U) ->
            {#user{uid = U}, undefined};
        undefined ->
            {undefined, undefined}
    end,
    #user_action{
        user = User,
        time = os:timestamp(),
        comment = Comment
    }.


%%
%%  Creates new instance, initializes its initial state.
%%
handle_create(Module, Args, CreateOpts, CustomOpts) ->
    Now         = eproc:now(),
    Group       = proplists:get_value(group,      CreateOpts, new),
    Name        = proplists:get_value(name,       CreateOpts, undefined),
    Store       = proplists:get_value(store,      CreateOpts, undefined),
    StartSpec   = proplists:get_value(start_spec, CreateOpts, undefined),
    {ok, InitSData} = call_init_persistent(Module, Args),
    InstState = #inst_state{
        stt_id          = 0,
        sname           = [],
        sdata           = InitSData,
        timestamp       = Now,
        attr_last_nr    = 0,
        attrs_active    = [],
        interrupts      = []
    },
    Instance = #instance{
        inst_id     = undefined,
        group       = Group,
        name        = Name,
        module      = Module,
        args        = Args,
        opts        = CustomOpts,
        start_spec  = StartSpec,
        status      = running,
        created     = Now,
        create_node = undefined,
        terminated  = undefined,
        term_reason = undefined,
        archived    = undefined,
        interrupt   = undefined,
        curr_state  = InstState,
        arch_state  = undefined,
        transitions = undefined
    },
    eproc_store:add_instance(Store, Instance).


%%
%%  Loads the instance and starts it if needed.
%%
handle_start(FsmRef, StartOpts, State = #state{store = Store}) ->
    case eproc_store:load_instance(Store, FsmRef) of
        {ok, Instance = #instance{inst_id = InstId, status = Status}} when Status =:= running; Status =:= resuming ->
            StateWithInstId = State#state{inst_id = InstId},
            ok = limits_setup(StateWithInstId),
            LimitsResult = case limits_notify_res(StateWithInstId) of
                {delay, D} ->
                    lager:debug("FSM id=~p is going to sleep for ~p ms on startup.", [InstId, D]),
                    timer:sleep(D),
                    ok;
                Other ->
                    Other
            end,
            case LimitsResult of
                ok ->
                    case start_loaded(Instance, StartOpts, StateWithInstId) of
                        {ok, NewState} ->
                            lager:debug("FSM started, ref=~p, pid=~p.", [FsmRef, self()]),
                            {online, NewState};
                        {error, Reason} ->
                            lager:warning("Failed to start FSM, ref=~p, error=~p.", [FsmRef, Reason]),
                            {offline, InstId}
                    end;
                {reached, Limits} ->
                    {ok, InstId} = eproc_store:set_instance_suspended(Store, FsmRef, {fault, restart_limit}),
                    lager:notice(
                        "Suspending FSM on startup, give up restarting, ref=~p, id=~p, limits ~p reached.",
                        [FsmRef, InstId, Limits]
                    ),
                    {offline, InstId}
            end;
        {ok, #instance{inst_id = InstId, status = Status}} ->
            lager:notice("FSM going to offline during startup, ref=~p, status=~p.", [FsmRef, Status]),
            {offline, InstId}
    end.


%%
%%  Starts already loaded instance.
%%
start_loaded(Instance, StartOpts, State) ->
    #instance{
        inst_id = InstId,
        group = Group,
        name = Name,
        curr_state = InstState,
        interrupt = Interrupt
    } = Instance,
    #inst_state{
        stt_id = LastTrnNr,
        sname = LastSName,
        sdata = LastSData
    } = InstState,
    #state{
        store = Store,
        registry = Registry
    } = State,

    undefined = erlang:put('eproc_fsm$id', InstId),
    undefined = erlang:put('eproc_fsm$group', Group),
    undefined = erlang:put('eproc_fsm$name', Name),

    ok = register_online(Instance, Registry, StartOpts),

    case Interrupt of
        undefined ->
            case init_loaded(Instance, LastSName, LastSData, State) of
                {ok, NewState} -> {ok, NewState};
                {error, Reason} -> {error, Reason}
            end;
        #interrupt{resumes = [ResumeAttempt | _]} ->
            case ResumeAttempt of
                #resume_attempt{upd_sname = undefined, upd_sdata = undefined, upd_script = undefined} ->
                    case init_loaded(Instance, LastSName, LastSData, State) of
                        {ok, NewState} ->
                            ok = limits_reset(State),
                            ok = eproc_store:set_instance_resumed(Store, InstId, LastTrnNr),
                            {ok, NewState};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                #resume_attempt{upd_sname = UpdSName, upd_sdata = UpdSData, resumed = #user_action{user = ResumedUser}} ->
                    NewSName = case UpdSName of
                        undefined -> LastSName;
                        _         -> UpdSName
                    end,
                    NewSData = case UpdSData of
                        undefined -> LastSData;
                        _         -> UpdSData
                    end,
                    case init_loaded(Instance, NewSName, NewSData, State) of
                        {ok, NewState} ->
                            ok = limits_reset(State),
                            Trigger = #trigger_spec{
                                type = admin,
                                source = {admin, ResumedUser},
                                message = resume,
                                msg_cid = undefined,
                                msg_type_fun = fun resolve_event_type/2,
                                sync = false,
                                reply_fun = undefined,
                                src_arg = false
                            },
                            TransitionFun = fun (_T, _TN, S) -> perform_resume_transition(ResumeAttempt, S) end,
                            case perform_transition(Trigger, TransitionFun, NewState) of
                                {cont, ResumedState} -> {ok, ResumedState};
                                {error, Reason}      -> {error, Reason}
                            end;
                        {error, Reason} ->
                            {error, Reason}
                    end
            end
    end.


%%
%%  Initializes loaded instance.
%%
init_loaded(Instance, SName, SData, State) ->
    #state{
        store = Store
    } = State,
    #instance{
        inst_id = InstId,
        module = Module,
        curr_state = InstState
    } = Instance,
    #inst_state{
        stt_id = LastTrnNr,
        attr_last_nr = LastAttrNr,
        attrs_active = ActiveAttrs
    } = InstState,
    case upgrade_state(Instance, SName, SData) of
        {ok, UpgradedSName, UpgradedSData} ->
            {ok, AttrState} = eproc_fsm_attr:init(InstId, UpgradedSName, LastAttrNr, Store, ActiveAttrs),
            {ok, UpgradedSDataWithRT, RTField, RTDefault} = call_init_runtime(UpgradedSName, UpgradedSData, Module),
            NewState = State#state{
                inst_id     = InstId,
                module      = Module,
                sname       = UpgradedSName,
                sdata       = UpgradedSDataWithRT,
                rt_field    = RTField,
                rt_default  = RTDefault,
                trn_nr      = LastTrnNr,
                attrs       = AttrState
            },
            {ok, NewState};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Initialize the persistent state of the FSM.
%%
call_init_persistent(Module, Args) ->
    case Module:init(Args) of
        {ok, SData} ->
            {ok, SData}
    end.


%%
%%  Initialize the runtime state of the FSM.
%%
call_init_runtime(SName, SData, Module) ->
    case Module:init(SName, SData) of
        ok ->
            {ok, SData, undefined, undefined};
        {ok, RuntimeField, RuntimeData} ->
            RuntimeDefault = erlang:element(RuntimeField, SData),
            SDataWithRT = erlang:setelement(RuntimeField, SData, RuntimeData),
            {ok, SDataWithRT, RuntimeField, RuntimeDefault}
    end.


%%
%%  Register instance id and name to a registry if needed.
%%
register_online(#instance{inst_id = InstId, name = Name}, Registry, StartOpts) ->
    Keys = case proplists:get_value(register, StartOpts) of
        none                                  -> [];
        id                                    -> [{inst, InstId}              ];
        name      when Name     =/= undefined -> [                {name, Name}];
        both      when Name     =/= undefined -> [{inst, InstId}, {name, Name}];
        undefined when Registry =:= undefined -> [];
        undefined when Name     =:= undefined -> [{inst, InstId}              ];
        undefined                             -> [{inst, InstId}, {name, Name}]
    end,
    ok = eproc_registry:register_fsm(Registry, InstId, Keys),
    ok.


%%
%%  Perform state upgrade on code change or state reload from db.
%%
upgrade_state(#instance{module = Module}, SName, SData) ->
    try Module:code_change(state, SName, SData, undefined) of
        {ok, NextSName, NewSData} ->
            {ok, NextSName, NewSData};
        {ok, NextSName, NewSData, _RTField} ->
            lager:warning("Runtime field is returned from the code_change/4, but it will be overriden in init/2."),
            {ok, NextSName, NewSData};
        {error, Reason} ->
            {error, Reason}
    catch
        ErrClass:Error ->
            {error, {bad_state, {ErrClass, Error, erlang:get_stacktrace()}}}
    end.


%%
%%  Perform a state transition.
%%
perform_transition(Trigger, TransitionFun, State) ->
    #state{
        inst_id = InstId,
        sname = SName,
        trn_nr = LastTrnNr,
        rt_field = RuntimeField,
        rt_default = RuntimeDefault,
        attrs = Attrs,
        store = Store
    } = State,
    #trigger_spec{
        type = TriggerType,
        source = TriggerSrc,
        message = TriggerMsg,
        msg_cid = TriggerMsgCId,
        msg_type_fun = MessageTypeFun,
        reply_fun = ReplyFun
    } = Trigger,

    TrnNr = LastTrnNr + 1,
    TrnStart = os:timestamp(),
    erlang:put('eproc_fsm$msg_regs', #msg_regs{inst_id = InstId, trn_nr = TrnNr, next_msg_nr = 2, registered = []}),
    erlang:put('eproc_fsm$suspend', false),
    {ok, TrnAttrs} = eproc_fsm_attr:transition_start(InstId, TrnNr, SName, Attrs),
    {ok, ProcAction, NewSName, NewSData, Reply, ExplicitAttrActions} = TransitionFun(Trigger, TrnNr, State),
    {ok, AttrActions, LastAttrNr, NewAttrs} = eproc_fsm_attr:transition_end(InstId, TrnNr, NewSName, TrnAttrs),
    TrnEnd = os:timestamp(),

    %%  Collect all messages.
    #msg_regs{registered = MsgRegs} = erlang:erase('eproc_fsm$msg_regs'),
    {RegisteredMsgs, RegisteredMsgRefs, InstId} = lists:foldr(fun registered_messages/2, {[], [], InstId}, MsgRegs),
    RequestMsgCId = case TriggerMsgCId of
        undefined             -> ?MSGCID_REQUEST(InstId, TrnNr);
        ?MSGCID_SENT(I, T, M) -> ?MSGCID_RECV(I, T, M)
    end,
    RequestMsgType = MessageTypeFun(TriggerType, TriggerMsg),
    RequestMsgRef = #msg_ref{cid = RequestMsgCId, peer = TriggerSrc, type = RequestMsgType},
    RequestMsg = #message{
        msg_id   = RequestMsgCId,
        sender   = TriggerSrc,
        receiver = {inst, InstId},
        resp_to  = undefined,
        type     = RequestMsgType,
        date     = TrnStart,
        body     = TriggerMsg
    },
    {ResponseMsgRef, TransitionMsgs} = case Reply of
        noreply ->
            {undefined, [RequestMsg | RegisteredMsgs]};
        {reply, ReplyMsgCId, ReplyMsg, _ReplySent} ->
            ResponseMsgType = MessageTypeFun(reply, ReplyMsg),
            ResponseRef = #msg_ref{cid = ReplyMsgCId, peer = TriggerSrc, type = ResponseMsgType},
            ResponseMsg = #message{
                msg_id   = ReplyMsgCId,
                sender   = {inst, InstId},
                receiver = TriggerSrc,
                resp_to  = RequestMsgCId,
                type     = ResponseMsgType,
                date     = TrnEnd,
                body     = ReplyMsg
            },
            {ResponseRef, [RequestMsg, ResponseMsg | RegisteredMsgs]}
    end,

    %%  Save transition.
    {FinalProcAction, InstStatus, Interrupts, Delay} = case ProcAction of
        cont ->
            case erlang:erase('eproc_fsm$suspend') of
                {true, SuspReason} ->
                    lager:notice("FSM id=~p suspended, impl reason ~p.", [InstId, SuspReason]),
                    {stop, suspended, [#interrupt{reason = {impl, SuspReason}}], undefined};
                false ->
                    case limits_notify_trn(State, TransitionMsgs) of
                        ok ->
                            {cont, running, undefined, undefined};
                        {delay, D} ->
                            {cont, running, undefined, D};
                        {reached, Reached} ->
                            lager:notice("FSM id=~p suspended, limits ~p reached.", [InstId, Reached]),
                            {stop, suspended, [#interrupt{reason = {fault, {limits, Reached}}}], undefined}
                    end
            end;
        stop ->
            {stop, completed, undefined, undefined}
    end,
    Transition = #transition{
        trn_id = TrnNr,
        sname = NewSName,
        sdata = cleanup_runtime_data(NewSData, RuntimeField, RuntimeDefault),
        timestamp = TrnStart,
        duration = timer:now_diff(TrnEnd, TrnStart),
        trigger_type = TriggerType,
        trigger_msg  = RequestMsgRef,
        trigger_resp = ResponseMsgRef,
        trn_messages = RegisteredMsgRefs,
        attr_last_nr = LastAttrNr,
        attr_actions = ExplicitAttrActions ++ AttrActions,
        inst_status  = InstStatus,
        interrupts   = Interrupts
    },
    % TODO: add_transition can reply with suggestion to stop the process.
    {ok, InstId, TrnNr} = eproc_store:add_transition(Store, InstId, Transition, TransitionMsgs),

    %% Send a reply, if not sent already
    case Reply of
        noreply -> ok;
        {reply, _SentReplyMsgCId, _SentReplyMsg, true} ->  ok;
        {reply, ReplyMsgCIdToSend, ReplyMsgToSend, false} ->
            ReplyFun(InstId, ReplyMsgCIdToSend, ReplyMsgToSend)
    end,

    %% Wait a bit, if needed.
    case Delay of
        undefined -> ok;
        _ ->
            lager:debug("FSM id=~p is going to sleep for ~p ms on transition.", [InstId, Delay]),
            timer:sleep(Delay)
    end,

    %% Ok, save changes in the state.
    NewState = State#state{
        sname = NewSName,
        sdata = NewSData,
        trn_nr = TrnNr,
        attrs = NewAttrs
    },
    {FinalProcAction, NewState}.


%%
%%  Performs actions specific for the resume-initiated transition.
%%
perform_resume_transition(ResumeAttempt, State) ->
    #state{
        sname = SName,
        sdata = SData
    } = State,
    #resume_attempt{
        upd_script = UpdScript
    } = ResumeAttempt,
    case UpdScript of
        undefined ->
            ok;
        _ when is_list(UpdScript) ->
            ScriptExecFun = fun
                ({R, {M, F, A}}) ->
                    R = erlang:apply(M, F, A);
                ({M, F, A}) ->
                    erlang:apply(M, F, A)
            end,
            ok = lists:foreach(ScriptExecFun, UpdScript)
    end,
    {ok, cont, SName, SData, noreply, []}.


%%
%%  Performs actions specific for event-initiated transition.
%%
perform_event_transition(Trigger, TrnNr, InitAttrActions, State) ->
    #state{
        inst_id = InstId,
        module = Module,
        sname = SName,
        sdata = SData
    } = State,
    #trigger_spec{
        type = TriggerType,
        source = TriggerSrc,
        message = TriggerMsg,
        sync = TriggerSync,
        reply_fun = ReplyFun,
        src_arg = TriggerSrcArg
    } = Trigger,
    erlang:put('eproc_fsm$reply', noreply),

    From = {InstId, TrnNr, ReplyFun},
    TriggerArg = case {TriggerSrcArg, TriggerSync} of
        {true,  true}  -> {TriggerType, TriggerSrc, From, TriggerMsg};
        {true,  false} -> {TriggerType, TriggerSrc, TriggerMsg};
        {false, true}  -> {TriggerType, From, TriggerMsg};
        {false, false} -> {TriggerType, TriggerMsg}
    end,
    {TrnMode, TransitionReply, NewSName, NewSData} = case Module:handle_state(SName, TriggerArg, SData) of
        {same_state,          NSD} -> {same,  noreply,    SName, NSD};
        {next_state,     NSN, NSD} -> {next,  noreply,    NSN,   NSD};
        {final_state,    NSN, NSD} -> {final, noreply,    NSN,   NSD};
        {reply_same,  R,      NSD} -> {same,  {reply, R}, SName, NSD};
        {reply_next,  R, NSN, NSD} -> {next,  {reply, R}, NSN,   NSD};
        {reply_final, R, NSN, NSD} -> {final, {reply, R}, NSN,   NSD}
    end,
    {ok, DerivedSName} = derive_next_state(NewSName, SName),

    ExplicitReply = erlang:erase('eproc_fsm$reply'),
    Reply = case {TriggerSync, TransitionReply, ExplicitReply} of
        {true, {reply, ReplyMsg}, noreply} ->
            ReplyMsgCId = ?MSGCID_REPLY(InstId, TrnNr),
            {reply, ReplyMsgCId, ReplyMsg, false};
        {true, noreply, {reply, ReplyMsgCId, ReplyMsg}} ->
            {reply, ReplyMsgCId, ReplyMsg, true};
        {false, noreply, noreply} ->
            noreply
    end,

    {ProcAction, SNameAfterTrn, SDataAfterTrn} = case TrnMode of
        same ->
            {cont, DerivedSName, NewSData};
        next ->
            {ok, SDataAfterExit} = perform_exit(SName, NewSName, NewSData, State),
            case perform_entry(SName, NewSName, DerivedSName, SDataAfterExit, State) of
                {ok, DerivedSNameAfterEntry, SDataAfterEntry} ->
                    {cont, DerivedSNameAfterEntry, SDataAfterEntry};
                {stop, DerivedSNameAfterEntry, SDataAfterEntry} ->
                    {stop, DerivedSNameAfterEntry, SDataAfterEntry}
            end;
        final ->
            {ok, SDataAfterExit} = perform_exit(SName, NewSName, NewSData, State),
            {stop, DerivedSName, SDataAfterExit}
    end,
    {ok, ProcAction, SNameAfterTrn, SDataAfterTrn, Reply, InitAttrActions}.


%%
%%  Invoke the state exit action.
%%
perform_exit([], _NextSName, SData, _State) ->
    {ok, SData};

perform_exit(PrevSName, NextSName, SData, #state{module = Module}) ->
    case Module:handle_state(PrevSName, {exit, NextSName}, SData) of
        {ok, NewSData} ->
            {ok, NewSData}
    end.


%%
%%  Invoke the state entry action.
%%
perform_entry(PrevSName, NextSName, DerivedSName, SData, State = #state{module = Module}) ->
    case Module:handle_state(NextSName, {entry, PrevSName}, SData) of
        {ok, NewSData} ->
            {ok, DerivedSName, NewSData};
        {same_state, NewSData} ->
            {ok, DerivedSName, NewSData};
        {next_state, NewSName, NewSData} ->
            {ok, NewDerivedSName} = derive_next_state(NewSName, PrevSName),
            perform_entry(PrevSName, NewSName, NewDerivedSName, NewSData, State);
        {final_state, NewSName, NewSData} ->
            {ok, NewDerivedSName} = derive_next_state(NewSName, PrevSName),
            {stop, NewDerivedSName, NewSData}
    end.


%%
%%  Resolves messages and references that were registered during
%%  particular transition.
%%
registered_messages(MsgReg = #msg_reg{resp_cid = undefined}, {Msgs, Refs, InstId}) ->
    #msg_reg{
        dst = Destication,
        sent_cid = SentMsgCId,
        sent_msg = SentMsgBody,
        sent_type = SentMsgType,
        sent_time = SentTime
    } = MsgReg,
    NewRef = #msg_ref{cid = SentMsgCId, peer = Destication, type = SentMsgType},
    NewMsg = #message{
        msg_id   = SentMsgCId,
        sender   = {inst, InstId},
        receiver = Destication,
        resp_to  = undefined,
        type     = SentMsgType,
        date     = SentTime,
        body     = SentMsgBody
    },
    {[NewMsg | Msgs], [NewRef | Refs], InstId};

registered_messages(MsgReg, {Msgs, Refs, InstId}) ->
    #msg_reg{
        dst = Destication,
        sent_cid  = SentMsgCId,
        sent_msg  = SentMsgBody,
        sent_type = SentMsgType,
        sent_time = SentTime,
        resp_cid  = RespMsgCId,
        resp_msg  = RespMsgBody,
        resp_type = RespMsgType,
        resp_time = RespTime
    } = MsgReg,
    NewReqRef = #msg_ref{cid = SentMsgCId, peer = Destication, type = SentMsgType},
    NewResRef = #msg_ref{cid = RespMsgCId, peer = Destication, type = RespMsgType},
    NewReqMsg = #message{
        msg_id   = SentMsgCId,
        sender   = {inst, InstId},
        receiver = Destication,
        resp_to  = undefined,
        type     = SentMsgType,
        date     = SentTime,
        body     = SentMsgBody
    },
    NewResMsg = #message{
        msg_id   = RespMsgCId,
        sender   = Destication,
        receiver = {inst, InstId},
        resp_to  = SentMsgCId,
        type     = RespMsgType,
        date     = RespTime,
        body     = RespMsgBody
    },
    {[NewReqMsg, NewResMsg | Msgs], [NewReqRef, NewResRef | Refs], InstId}.


%%
%%  Cleanup runtime state before storing state to the DB.
%%
cleanup_runtime_data(Data, undefined, _RuntimeDefault) ->
    Data;

cleanup_runtime_data(Data, RuntimeField, RuntimeDefault) when is_integer(RuntimeField), is_tuple(Data) ->
    erlang:setelement(RuntimeField, Data, RuntimeDefault).


%%
%%  Splits a proplist to create, start, send, common and unknown options.
%%
split_options(Options) ->
    {Create, Start, Send, Common, Unknown} = lists:foldr(
        fun split_options/2,
        {[], [], [], [], []},
        Options
    ),
    {ok, Create, Start, Send, Common, Unknown}.


split_options(Prop = {N, _}, {Create, Start, Send, Common, Unknown}) when
        N =:= group;
        N =:= name;
        N =:= start_spec
        ->
    {[Prop | Create], Start, Send, Common, Unknown};

split_options(Prop = {N, _}, {Create, Start, Send, Common, Unknown}) when
        N =:= register;
        N =:= start_sync;
        N =:= limit_restarts;
        N =:= limit_transitions;
        N =:= limit_sent_msgs
        ->
    {Create, [Prop | Start], Send, Common, Unknown};

split_options(Prop = {N, _}, {Create, Start, Send, Common, Unknown}) when
        N =:= source
        ->
    {Create, Start, [Prop | Send], Common, Unknown};

split_options(Prop = {N, _}, {Create, Start, Send, Common, Unknown}) when
        N =:= timeout;
        N =:= store;
        N =:= registry;
        N =:= user
        ->
    {Create, Start, Send, [Prop | Common], Unknown};

split_options(Prop = {_, _}, {Create, Start, Send, Common, Unknown}) ->
    {Create, Start, Send, Common, [Prop | Unknown]}.


%%
%%  Creates an FSM, prepares info for sending first event.
%%
create_prepare_send(Module, Args, Options) ->
    {ok, CreateOpts, [], SendOpts, CommonOpts, UnknownOpts} = split_options(Options),

    CreateOptsWithGroup = resolve_append_group(CreateOpts),
    AllCreateOpts = lists:append([CreateOptsWithGroup, CommonOpts, UnknownOpts]),
    case create(Module, Args, AllCreateOpts) of
        {ok, FsmRef} ->
            Registry = resolve_registry(CommonOpts),
            AllSendOpts = lists:append(SendOpts, CommonOpts),
            {ok, StartSpec} = resolve_start_spec(CreateOpts),
            {ok, NewFsmRef} = eproc_registry:make_new_fsm_ref(Registry, FsmRef, StartSpec),
            {ok, FsmRef, NewFsmRef, AllSendOpts};
        {error, Reason} ->
            {error, Reason}
    end.


%%
%%  Start FSM synchronously, if requested.
%%
start_sync({ok, Pid}, StartOpts) ->
    case proplists:get_value(start_sync, StartOpts, false) of
        false ->
            {ok, Pid};
        true ->
            try gen_server:call(Pid, {'eproc_fsm$is_online'}) of
                true -> {ok, Pid}
            catch
                C:E ->
                    lager:error("FSM start failed with reason ~p:~p at ~p", [C, E, erlang:get_stacktrace()]),
                    {error, start_failed}
            end
    end;

start_sync(Other, _StartOpts) ->
    Other.


%%  Notify restart counter.
%%
limits_notify_res(#state{lim_res = undefined}) ->
    ok;

limits_notify_res(#state{inst_id = InstId}) ->
    eproc_limits:notify(?LIMIT_PROC(InstId), ?LIMIT_RES, 1).


%%
%%  Notify transition and sent messages counters.
%%
limits_notify_trn(#state{lim_trn = undefined, lim_msg_all = undefined, lim_msg_dst = undefined}, _Msgs) ->
    ok;

limits_notify_trn(#state{inst_id = InstId, lim_msg_all = undefined, lim_msg_dst = undefined}, _Msgs) ->
    eproc_limits:notify(?LIMIT_PROC(InstId), [{?LIMIT_TRN, 1}]);

limits_notify_trn(State, Msgs) ->
    #state{
        inst_id = InstId,
        lim_trn = LimTrn,
        lim_msg_all = LimMsgAll,
        lim_msg_dst = LimMsgDst
    } = State,
    DstMsgCountersFun = fun (#message{receiver = Receiver}, Counters) ->
        case lists:keyfind(Receiver, 1, Counters) of
            false   -> Counters;
            {CN, C} -> lists:keyreplace(CN, 1, Counters, {CN, C + 1})
        end
    end,
    TrnCounters = case LimTrn of
        undefined -> [];
        _ -> [{?LIMIT_TRN, 1}]
    end,
    MsgAllCounters = case LimMsgAll of
        undefined -> [];
        _ -> [{?LIMIT_MSG_ALL, length(Msgs)}]
    end,
    MsgDstCounters = case LimMsgDst of
        undefined -> [];
        _ ->
            MDCs = lists:foldl(DstMsgCountersFun, [ {D, 0} || {D, _L} <- LimMsgDst ], Msgs),
            [ {?LIMIT_MSG_DST(D), C} || {D, C} <- MDCs ]
    end,
    AllCounters = lists:append([TrnCounters, MsgAllCounters, MsgDstCounters]),
    eproc_limits:notify(?LIMIT_PROC(InstId), AllCounters).


%%
%%  Invokes specified function on all counters that have limits defined.
%%
limits_action(State, Fun) ->
    #state{
        inst_id = InstId,
        lim_res = LimRes,
        lim_trn = LimTrn,
        lim_msg_all = LimMsgAll,
        lim_msg_dst = LimMsgDst
    } = State,
    CounterProc = ?LIMIT_PROC(InstId),
    SetupCounterFun = fun
        (_CounterName, undefined) -> ok;
        (CounterName,  LimitSpec) -> Fun(CounterProc, CounterName, LimitSpec)
    end,
    SetupMsgDstCounterFun = fun ({Dst, LimitSpec}) ->
        ok = SetupCounterFun(?LIMIT_MSG_DST(Dst), LimitSpec)
    end,
    ok = SetupCounterFun(?LIMIT_RES,     LimRes),
    ok = SetupCounterFun(?LIMIT_TRN,     LimTrn),
    ok = SetupCounterFun(?LIMIT_MSG_ALL, LimMsgAll),
    ok = case LimMsgDst of
        undefined -> ok;
        _ when is_list(LimMsgDst) -> lists:foreach(SetupMsgDstCounterFun, LimMsgDst)
    end.


%%
%%  Setup limit counters.
%%
limits_setup(State) ->
    limits_action(State, fun eproc_limits:setup/3).


%%
%%  Reset limit counters.
%%
limits_reset(State) ->
    limits_action(State, fun (P, C, _L) -> eproc_limits:reset(P, C) end).


%%
%%  Cleanup limit counters.
%%
limits_cleanup(State) ->
    limits_action(State, fun (P, C, _L) -> eproc_limits:cleanup(P, C) end).



%% =============================================================================
%%  Unit tests for private functions.
%% =============================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%%
%%  Unit tests for `resolve_fsm_ref/1`.
%%
resolve_fsm_ref_test() ->
    ok = meck:new(eproc_router, []),
    ok = meck:new(eproc_registry, []),
    ok = meck:expect(eproc_router, lookup, fun
        (key3, []              ) -> {ok, [iid3]};
        (key4, [{store, store}]) -> {ok, [iid4]};
        (key5, []              ) -> {ok, []};
        (key6, []              ) -> {ok, [iid6a, iid6b]}
    end),
    ok = meck:expect(eproc_registry, make_fsm_ref, fun
        (registry, {inst, iid1}) -> {ok, ref1};
        (registry, {name, nme2}) -> {ok, ref2};
        (registry, {inst, iid3}) -> {ok, ref3};
        (registry, {inst, iid4}) -> {ok, ref4}
    end),
    ?assertEqual({ok,    ref1     }, resolve_fsm_ref({inst, iid1}, [{registry, registry}])),
    ?assertEqual({ok,    ref2     }, resolve_fsm_ref({name, nme2}, [{registry, registry}])),
    ?assertEqual({ok,    ref3     }, resolve_fsm_ref({key,  key3}, [{registry, registry}])),
    ?assertEqual({ok,    ref4     }, resolve_fsm_ref({key,  key4, [{store, store}]}, [{registry, registry}])),
    ?assertEqual({error, not_found}, resolve_fsm_ref({key,  key5}, [{registry, registry}])),
    ?assertEqual({error, multiple }, resolve_fsm_ref({key,  key6}, [{registry, registry}])),
    ?assertEqual({ok,    some     }, resolve_fsm_ref(some, [{registry, registry}])),
    ?assert(meck:validate([eproc_router, eproc_registry])),
    meck:unload([eproc_router, eproc_registry]).

%%
%%  Unit tests for `resolve_event_src/1`.
%%
resolve_event_src_test_() -> [
    fun () ->
        ?assertEqual({ok, undefined}, resolve_event_src([]))
    end,
    fun () ->
        erlang:put('eproc_fsm$id', 145),
        ?assertEqual({ok, {inst, 145}}, resolve_event_src([])),
        erlang:erase('eproc_fsm$id')
    end,
    fun () ->
        eproc_event_src:set_source({some, source}),
        ?assertEqual({ok, {some, source}}, resolve_event_src([])),
        eproc_event_src:remove()
    end,
    fun () ->
        erlang:put('eproc_fsm$id', 146),
        eproc_event_src:set_source({some, source2}),
        ?assertEqual({ok, {some, source2}}, resolve_event_src([])),
        eproc_event_src:remove(),
        erlang:erase('eproc_fsm$id')
    end,
    fun () ->
        erlang:put('eproc_fsm$id', 146),
        eproc_event_src:set_source({some, source2}),
        ?assertEqual({ok, {explicit, srt}}, resolve_event_src([{source, {explicit, srt}}])),
        eproc_event_src:remove(),
        erlang:erase('eproc_fsm$id')
    end].


%%
%%  Unit tests for `resolve_event_type_fun/1`.
%%
resolve_event_type_fun_test_() ->
    {ok, Fun1} = resolve_event_type_fun([{type, asd}]),
    {ok, Fun2} = resolve_event_type_fun([{type, fun (_R, _M) -> <<"qqq">> end}]),
    {ok, Fun3} = resolve_event_type_fun([]),
    [
        ?_assertEqual(<<"asd">>, Fun1(event, uuu)),
        ?_assertEqual(<<"qqq">>, Fun2(event, uuu)),
        ?_assertEqual(<<"uuu">>, Fun3(event, uuu))
    ].


%%
%%  Unit tests for `split_options/1`.
%%
split_options_test_() -> [
    ?_assertMatch(
        {ok, [], [], [], [], []},
        split_options([])
    ),
    ?_assertMatch(
        {ok,
            [{group, x}, {name, x}, {start_spec, x}],
            [{limit_restarts, x}, {limit_transitions, x}, {limit_sent_msgs, x}, {register, x}, {start_sync, x}],
            [{source, x}],
            [{timeout, x}, {store, x}, {registry, x}, {user, x}],
            [{some, y}]
        },
        split_options([
            {group, x}, {name, x}, {start_spec, x}, {limit_restarts, x}, {limit_transitions, x}, {limit_sent_msgs, x},
            {register, x}, {start_sync, x}, {source, x}, {timeout, x}, {store, x}, {registry, x}, {user, x}, {some, y}
        ])
    )].

%%
%%  Unit tests for `limits_action/2`.
%%
limits_action_test() ->
    State = #state{inst_id = iid, lim_res = r, lim_trn = t, lim_msg_all = ma, lim_msg_dst = [{d1, md1}, {d2, md2}]},
    ok = meck:new(eproc_fsm_limits_action_mock, [non_strict]),
    ok = meck:expect(eproc_fsm_limits_action_mock, some, fun (?LIMIT_PROC(iid), _, _) -> ok end),
    ok = limits_action(State, fun eproc_fsm_limits_action_mock:some/3),
    ?assertEqual(1, meck:num_calls(eproc_fsm_limits_action_mock, some, ['_', ?LIMIT_RES, r])),
    ?assertEqual(1, meck:num_calls(eproc_fsm_limits_action_mock, some, ['_', ?LIMIT_TRN, t])),
    ?assertEqual(1, meck:num_calls(eproc_fsm_limits_action_mock, some, ['_', ?LIMIT_MSG_ALL, ma])),
    ?assertEqual(1, meck:num_calls(eproc_fsm_limits_action_mock, some, ['_', ?LIMIT_MSG_DST(d1), md1])),
    ?assertEqual(1, meck:num_calls(eproc_fsm_limits_action_mock, some, ['_', ?LIMIT_MSG_DST(d2), md2])),
    ?assertEqual(5, meck:num_calls(eproc_fsm_limits_action_mock, some, '_')),
    ?assert(meck:validate(eproc_fsm_limits_action_mock)),
    ok = meck:unload(eproc_fsm_limits_action_mock).

%%
%%  Unit tests for `limits_notify_trn/2`.
%%
limits_notify_trn_test() ->
    State = #state{inst_id = iid, lim_res = r, lim_trn = t, lim_msg_all = ma, lim_msg_dst = [{d1, md1}, {d2, md2}]},
    Msgs = [#message{receiver = d1}, #message{receiver = d1}, #message{receiver = d2}, #message{receiver = d3}],
    ok = meck:new(eproc_limits, []),
    ok = meck:expect(eproc_limits, notify, fun (?LIMIT_PROC(iid), _) -> perfect end),
    ?assertEqual(perfect, limits_notify_trn(State, Msgs)),
    [{_, {_, _, [_, Counters]}, _}] = meck:history(eproc_limits),
    ?assertEqual(
        [{?LIMIT_TRN, 1}, {?LIMIT_MSG_ALL, 4}, {?LIMIT_MSG_DST(d1), 2}, {?LIMIT_MSG_DST(d2), 1}],
        lists:sort(Counters)
    ),
    ?assert(meck:validate(eproc_limits)),
    ok = meck:unload(eproc_limits).


-endif.


