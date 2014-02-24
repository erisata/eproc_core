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
%%  Main behaviour to be implemented by a user of the `eproc`
%%  =========================================================
%%
%%  This module designed by taking into account UML FSM definition
%%  as well as the Erlang/OTP `gen_fsm`. The following is the list
%%  of differences comparing it to `gen_fsm`:
%%
%%    * State name supports substates and orthogonal states.
%%    * Callback `Module:handle_state/3` is used instead of `Module:StateName/2-3`.
%%      This allows to have substates and orthogonal states.
%%    * Has support for state entry and exit actions.
%%      State entry action is convenient for setting up timers and keys.
%%    * Has support for scopes. The scopes can be used to manage timers and keys.
%%    * Supports automatic state persistence.
%%
%%  It is recomended to name version explicitly when defining state.
%%  It can be done as follows:
%%
%%      -record(state, {
%%          version = 1,
%%          ...
%%      }).
%%
%%
%%  How `eproc_fsm` callbacks are invoked in different scenarios
%%  ------------------------------------
%%
%%  New FSM created, started and an initial event received
%%  :
%%      On creation of the persistent FSM inialization in performed:
%%
%%        * `init(Args)`
%%
%%      then process is started, the following callbacks are used to
%%      possibly upgrade and initialize process runtime state:
%%
%%        * `code_change(state, StateName, StateData, undefined)`
%%        * `init(InitStateName, StateData)`
%%
%%      and then the first event is received and the following callbacks invoked:
%%
%%        * `handle_state(InitStateName, {event, Message} | {sync, From, Message}, StateData)`
%%        * `handle_state(NewStateName, {entry, InitStateName}, StateData)`
%%
%%  FSM process terminated
%%  :
%%        * `terminate(Reason, StateName, StateData)`
%%
%%  FSM is restarted or resumed after being suspended
%%  :
%%        * `code_change(state, StateName, StateData, undefined)`
%%        * `init(StateName, StateData)`
%%
%%  FSM upgraded in run-time
%%  :
%%        * `code_change(OldVsn, StateName, StateData, Extra)`
%%
%%  Event initiated a transition (`next_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%        * `handle_state(StateName, {exit, NextStateName}, StateData)`
%%        * `handle_state(NextStateName, {entry, StateName}, StateData)`
%%
%%  Event with no transition (`same_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%
%%  Event initiated a termination (`final_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData)`
%%        * `handle_state(StateName, {exit, FinalStateName}, StateData)`
%%
%%
%%  Dependencies
%%  ------------------------------------
%%
%%  This section lists modules, that can be used together with this module.
%%  All of them are optional and are references using options. Some functions
%%  require specific dependencies, but these functions are more for convenience.
%%
%%  `eproc_registry`
%%  :   can be used as a process registry, a supervisor and a process loader.
%%      This component is used via options: `start_spec` from the create options,
%%      `register` from the start options and `registry` from the common options.
%%      Functions `send_create_event/3` and `sync_send_create_event/4` can only
%%      be called if FSM used with the registry.
%%
%%  `eproc_restart`
%%  :   can be used to limit FSM restarts. This component is only used if
%%      start option `restart` is provided with the corresponding value.
%%
%%
%%  Common FSM options
%%  ------------------------------------
%%
%%  The following are the options, that can be provided for most of the
%%  functions in this module. Meaning of these options is the same in all cases.
%%  Description of each function states, which of these options are used in that
%%  function and other will be ignored.
%%
%%  `{store, StoreRef}`
%%  :   a store to be used by the FSM. If this option not provided, a store
%%      specified in the `eproc_core` application environment is used.
%%
%%  `{registry, StoreRef}`
%%  :   a registry to be used by the instance. If this option not provided, a registry
%%      specified in the `eproc_core` application environment is used. `eproc_core` can
%%      have no registry specified. In that case the registry will not be used.
%%
%%  `{timeout, Timeout}`
%%  :   Timeout for the function, 5000 (5 seconds) is the default.
%%
%%  `{user, (User :: binary() | {User :: binary(), Comment :: binary()})}`
%%  :   indicates a user initiaten an action. This option is mainly
%%      used for administrative actions: kill, suspend, resume and set_state.
%%
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
    sync_send_event/3, sync_send_event/2,
    kill/2, suspend/2, resume/2, set_state/4, is_online/2, is_online/1
]).

%%
%%  Functions to be used by the specific FSM implementations
%%  in the callback (process-side) functions.
%%
-export([
    reply/2
]).

%%
%%  APIs for related `eproc` modules.
%%
-export([
    is_state_in_scope/2,
    is_state_valid/1,
    is_next_state_valid/1,
    is_fsm_ref/1,
    register_message/4,
    resolve_start_spec/2
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


-type name() :: {via, Registry :: module(), InstId :: inst_id()}.
-opaque id()  :: integer().
-opaque group() :: integer().

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
    {mfa, {Module :: module(), Function :: atom(), Args :: list()}}.


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
%%      `{timer, Timer, Message}`
%%      :   indicates a time event `Message`, that was fired by a `Timer`.
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
%%  If the callback was invoked to handle state exit or entry, the response term should be
%%  `{ok, NewStateData}`.
%%
%%  The state exit action is not invoked for the initial transition. The initial transition
%%  can be recognized by the state entry action, it will be invoked with `[]` as a PrevStateName
%%  or the state name as returned by the `init/2` callback.
%%  Similarly, the entry action is not invoked for the final state.
%%
-callback handle_state(
        StateName   :: state_name(),
        Trigger     :: {event, Message} |
                       {sync, From, Message} |
                       {info, Message} |
                       {timer, Timer, Message} |
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
        Timer   :: event_src(),
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
        {ok, NextStateName, NewStateData, RuntimeField}
    when
        Vsn     :: term(),
        Extra   :: term(),
        NextStateName :: state_name(),
        NewStateData  :: state_data(),
        RuntimeField  :: integer().

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
%%  `{max_transitions, integer() | infinity}` - TODO
%%  :   Maximal allowed number of transitions.
%%      When this limit will be reached, the FSM will be suspended.
%%
%%  `{max_errors, integer() | infinity}` - TODO
%%  :   Maximal allowed number of errors in the FSM.
%%      When this limit will be reached, the FSM will be suspended.
%%
%%  `{max_sent_msgs, integer() | infinity}` - TODO
%%  :   Maximal allowed number of messages sent by the FSM.
%%      When this limit will be reached, the FSM will be suspended.
%%
-spec create(
        Module  :: module(),
        Args    :: term(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref()} |
        {error, already_created}.

create(Module, Args, Options) ->
    {ok, CreateOpts, [], [], CommonOpts, UnknownOpts} = split_options(Options),
    {ok, InstId} = handle_create(Module, Args, lists:append(CreateOpts, CommonOpts), UnknownOpts),
    {ok, {inst, InstId}}.


%%
%%  Start previously created (using `create/3`) `eproc_fsm` instance.
%%
%%  As part of initialization procedure, the FSM registers itself to the
%%  registry. Registration by InstId is done synchronously and registrations
%%  by Name and Keys are done asynchronously. One can use `is_online/1` to
%%  synchronize with the FSM.
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
%%  `{restart, list()}`
%%  :   specifies options used to limit process restart rate and duration. These
%%      options are passed to `eproc_restart:restarted/2`. See docs for that function
%%      for more details. If this option is not specified, [] is used as a default.
%%  `{register, (id | name | both)}`
%%  :   specifies, what to register to the `eproc_registry` on startup.
%%      The registration is performed asynchronously and the id or name are those
%%      loaded from the store during startup. These registration options are independent
%%      from the FsmName parameter. The FSM register nothing if this option is not
%%      provided. The startup will fail if this option is provided but registry
%%      is not configured for the `eproc_core` application (app environment).
%%  `{store, StoreRef}`
%%  :   a store to be used by the instance. If this option not provided, a store specified
%%      in the `eproc_core` application environment is used.
%%  `{registry, StoreRef}`
%%  :   a registry to be used by the instance. If this option not provided, a registry
%%      specified in the `eproc_core` application environment is used. `eproc_core` can
%%      cave no registry specified. In that case the registry will not be used.
%%
-spec start_link(
        FsmName     :: {local, atom()} | {global, term()} | {via, module(), term()},
        FsmRef      :: fsm_ref(),
        Options     :: proplist()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(FsmName, FsmRef, Options) ->
    {ok, StartOpts, ProcessOptions} = resolve_start_link_opts(Options),
    gen_server:start_link(FsmName, ?MODULE, {FsmRef, StartOpts}, ProcessOptions).


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
    gen_server:start_link(?MODULE, {FsmRef, StartOpts}, ProcessOptions).


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
%%  Checks if the state name is valid for transition target.
%%
-spec is_next_state_valid(state_name()) -> boolean().

is_next_state_valid([_|_] = State) ->
    is_state_valid(State);

is_next_state_valid(_State) ->
    false.


%%
%%  Checks, if a term is an FSM reference.
%%
-spec is_fsm_ref(fsm_ref() | term()) -> boolean().

is_fsm_ref({inst, _}) -> true;
is_fsm_ref({name, _}) -> true;
is_fsm_ref(_) -> false.


%%
%%  Creates new FSM, starts it and sends first message to it. The startup is
%%  performed synchonously, therefore FSM instance id and name are registered
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
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

send_create_event(Module, Args, Event, Options) ->
    {ok, FsmRef, NewFsmRef, AllSendOpts} = create_prepare_send(Module, Args, Options),
    ok = send_event(NewFsmRef, Event, AllSendOpts),
    {ok, FsmRef}.



%%
%%  Creates new FSM, starts it and sends first message synchonously to it. All the
%%  parameters and behaviour are similar to ones, described for `send_create_event/4`,
%%  except that first event is send synchonously, i.e. `sync_send_event/2-3` is used
%%  instead of `send_event/2-3`.
%%
-spec sync_send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref(), Reply :: term()} |
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

sync_send_create_event(Module, Args, Event, Options) ->
    {ok, FsmRef, NewFsmRef, AllSendOpts} = create_prepare_send(Module, Args, Options),
    Reply = sync_send_event(NewFsmRef, Event, AllSendOpts),
    {ok, FsmRef, Reply}.


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
%%
%%  TODO: Options for metadata, event redelivery.
%%
-spec send_event(
        FsmRef  :: fsm_ref() | otp_ref(),
        Event   :: term(),
        Options :: proplist()
    ) ->
        ok.

send_event(FsmRef, Event, Options) ->
    {ok, EventSrc} = resolve_event_src(Options),
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    gen_server:cast(ResolvedFsmRef, {'eproc_fsm$send_event', Event, EventSrc}).


%%
%%  Simplified version of the `send_event/3`,
%%  equivalent to `send_event(FsmRef, Event, [])`.
%%
-spec send_event(
        FsmRef  :: fsm_ref() | otp_ref(),
        Event   :: term()
    ) ->
        ok.

send_event(FsmRef, Event) ->
    send_event(FsmRef, Event, []).


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
%%  `{timeout, Timeout}`
%%  :   Maximal time in milliseconds for the synchronous call.
%%      5000 (5 seconds) is the default.
%%
-spec sync_send_event(
        FsmRef  :: fsm_ref() | otp_ref(),
        Event   :: term(),
        Options :: proplist()
    ) ->
        Reply :: term().

sync_send_event(FsmRef, Event, Options) ->
    {ok, EventSrc} = resolve_event_src(Options),
    {ok, Timeout}  = resolve_timeout(Options),
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    gen_server:call(ResolvedFsmRef, {'eproc_fsm$sync_send_event', Event, EventSrc}, Timeout).


%%
%%  Simplified version of the `sync_send_event/3`,
%%  equivalent to `sync_send_event(FsmRef, Event, [])`.
%%
-spec sync_send_event(
        FsmRef  :: fsm_ref() | otp_ref(),
        Event   :: term()
    ) ->
        ok.

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
%%      Only the `registry` and `user` options will be used here
%%      and other options will be ignored.
%%
%%  This function depends on `eproc_registry`.
%%
-spec kill(
        FsmRef  :: fsm_ref() | otp_ref(),
        Options :: list()
    ) ->
        ok |
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
                {ok, _InstId} ->
                    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
                    gen_server:cast(ResolvedFsmRef, {'eproc_fsm$kill'});
                {error, Reason} ->
                    {error, Reason}
            end
    end.


%%
%%  TODO: Add spec.
%%
suspend(FsmRef, Options) ->
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    gen_server:call(ResolvedFsmRef, {'eproc_fsm$suspend'}).


%%
%%  TODO: Add spec.
%%
resume(FsmRef, Options) ->
    {ok, _ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    ok.
    % TODO: gen_server:call(ResolvedFsmRef, {'eproc_fsm$resume', Reason}).


%%
%%  TODO: Add spec.
%%
set_state(FsmRef, NewStateName, NewStateData, Options) ->
    % TODO: Make it offline.
    {ok, ResolvedFsmRef} = resolve_fsm_ref(FsmRef, Options),
    gen_server:call(ResolvedFsmRef, {'eproc_fsm$set_state', NewStateName, NewStateData}).


%%
%%  Checks is process is online. This function makes a synchronous call to
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

reply(To, Reply) ->
    noreply = erlang:put('eproc_fsm$reply', {reply, Reply}),
    To(Reply).


%%
%%  This function is used by modules sending outgoing messages
%%  from the FSM, like connectors.
%%
%%  Target FSM is responsible for storing message to the DB. If the event
%%  recipient is not FSM, the sending FSM is responsible for storing the event.
%%
-spec register_message(
        Src    :: event_src(),
        Dst    :: event_src(),
        Req    :: {ref, msg_id()} | {msg, term(), timestamp()},
        Res    :: {ref, msg_id()} | {msg, term(), timestamp()} | undefined
    ) ->
        {ok, skipped | registered} |
        {error, Reason :: term()}.

%%  Event between FSMs.
register_message({inst, _SrcInstId}, Dst = {inst, _DstInstId}, Req = {ref, _ReqId}, Res) ->
    Messages = erlang:get('eproc_fsm$messages'),
    Messages = erlang:put('eproc_fsm$messages', [{msg_reg, Dst, Req, Res} | Messages]),
    {ok, registered};

%%  Source is not FSM and target is FSM.
register_message(_EventSrc, {inst, _DstInstId}, {ref, _ReqId}, _Res) ->
    {ok, skipped};

%%  Source is FSM and target is not.
register_message({inst, _SrcInstId}, Dst, Req = {msg, _ReqBody, _ReqDate}, Res) ->
    Messages = erlang:get('eproc_fsm$messages'),
    Messages = erlang:put('eproc_fsm$messages', [{msg_reg, Dst, Req, Res} | Messages]),
    {ok, registered}.


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
    restart     :: list()           %% Restart options.
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({FsmRef, StartOpts}) ->
    State = #state{
        store    = resolve_store(StartOpts),
        registry = resolve_registry(StartOpts),
        restart  = proplists:get_value(restart, StartOpts, [])
    },
    self() ! {'eproc_fsm$start', FsmRef, StartOpts},
    {ok, State}.


%%
%%  Syncronous calls.
%%
handle_call({'eproc_fsm$is_online'}, _From, State) ->
    {reply, true, State};

handle_call({'eproc_fsm$sync_send_event', Event, EventSrc}, From, State) ->
    Trigger = #trigger_spec{
        type = sync,
        source = EventSrc,
        message = Event,
        sync = true,
        reply_fun = fun (R) -> gen_server:reply(From, R), ok end,
        src_arg = false
    },
    case perform_transition(Trigger, [], State) of
        {cont, noreply,        NewState} -> {noreply, NewState};
        {cont, {reply, Reply}, NewState} -> {reply, Reply, NewState};
        {stop, noreply,        NewState} -> shutdown(NewState);
        {stop, {reply, Reply}, NewState} -> shutdown(Reply, NewState);
        {error, Reason}                  -> {stop, {error, Reason}, State}
    end.


%%
%%  Asynchronous messages.
%%
handle_cast({'eproc_fsm$send_event', Event, EventSrc}, State) ->
    Trigger = #trigger_spec{
        type = event,
        source = EventSrc,
        message = Event,
        sync = false,
        reply_fun = undefined,
        src_arg = false
    },
    case perform_transition(Trigger, [], State) of
        {cont, noreply, NewState} -> {noreply, NewState};
        {stop, noreply, NewState} -> shutdown(NewState);
        {error, Reason}           -> {stop, {error, Reason}, State}
    end;

handle_cast({'eproc_fsm$kill'}, State = #state{inst_id = InstId}) ->
    lager:notice("FSM id=~p killed.", [InstId]),
    {stop, normal, State}.


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
handle_info(Event, State = #state{attrs = Attrs}) ->
    case eproc_fsm_attr:event(Event, Attrs) of
        {handled, NewAttrs} ->
            {noreply, State#state{attrs = NewAttrs}};
        {trigger, NewAttrs, Trigger, AttrAction} ->
            case perform_transition(Trigger, [AttrAction], State#state{attrs = NewAttrs}) of
                {cont, noreply, NewState} -> {noreply, NewState};
                {stop, noreply, NewState} -> shutdown(NewState);
                {error, Reason}           -> {stop, {error, Reason}, State#state{attrs = NewAttrs}}
            end;
        unknown ->
            Trigger = #trigger_spec{
                type = info,
                source = undefined,
                message = Event,
                sync = false,
                reply_fun = undefined,
                src_arg = false
            },
            case perform_transition(Trigger, [], State) of
                {cont, noreply, NewState} -> {noreply, NewState};
                {stop, noreply, NewState} -> shutdown(NewState);
                {error, Reason}           -> {stop, {error, Reason}, State}
            end
    end.


%%
%%  Invoked, when the FSM terminates.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Shutdown the FSM.
%%
shutdown(State = #state{inst_id = InstId, restart = RestartOpts}) ->
    eproc_restart:cleanup({?MODULE, InstId}, RestartOpts),
    {stop, normal, State}.


%%
%%  Shutdown the FSM with a reply msg.
%%
shutdown(Reply, State = #state{inst_id = InstId, restart = RestartOpts}) ->
    eproc_restart:cleanup({?MODULE, InstId}, RestartOpts),
    {stop, normal, Reply, State}.


%%
%%  Extracts timeout from the options.
%%
resolve_timeout(Options) ->
    Timeout = proplists:get_value(timeout, Options, ?DEFAULT_TIMEOUT),
    {ok, Timeout}.


%%
%%
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
            case {eproc_event_src:source(), eproc_fsm:id()} of
                {undefined, {ok, InstId}}     -> {ok, {inst, InstId}};
                {undefined, {error, not_fsm}} -> {ok, undefined};
                {EventSrc,  _}                -> {ok, EventSrc}
            end;
        {source, EventSrc} ->
            {ok, EventSrc}
    end.


%%
%%  Resolves instance reference.
%%
resolve_fsm_ref(FsmRef, Options) ->
    case is_fsm_ref(FsmRef) of
        true ->
            Registry = resolve_registry(Options),
            {ok, _ResolvedFsmRef} = eproc_registry:make_fsm_ref(Registry, FsmRef);
        false ->
            {ok, FsmRef}
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
        {U, C} when is_binary(U), is_binary(C) ->
            {U, C};
        U when is_binary(U) ->
            {U, undefined};
        undefined ->
            {undefined, undefined}
    end,
    #user_action{
        user = User,
        time = erlang:now(),
        comment = Comment
    }.


%%
%%  Creates new instance, initializes its initial state.
%%
handle_create(Module, Args, CreateOpts, CustomOpts) ->
    Group       = proplists:get_value(group,      CreateOpts, new),
    Name        = proplists:get_value(name,       CreateOpts, undefined),
    Store       = proplists:get_value(store,      CreateOpts, undefined),
    StartSpec   = proplists:get_value(start_spec, CreateOpts, undefined),
    {ok, InitSData} = call_init_persistent(Module, Args),
    Instance = #instance{
        id          = undefined,
        group       = Group,
        name        = Name,
        module      = Module,
        args        = Args,
        opts        = CustomOpts,
        init        = InitSData,
        start_spec  = StartSpec,
        status      = running,
        created     = eproc:now(),
        terminated  = undefined,
        term_reason = undefined,
        archived    = undefined,
        transitions = undefined
    },
    {ok, _InstId} = eproc_store:add_instance(Store, Instance).


%%
%%  Loads the instance and starts it if needed.
%%
handle_start(FsmRef, StartOpts, State = #state{store = Store, restart = RestartOpts}) ->
    case eproc_store:load_instance(Store, FsmRef) of
        {ok, Instance = #instance{id = InstId, status = running}} ->
            case eproc_restart:restarted({?MODULE, InstId}, RestartOpts) of
                ok ->
                    {ok, NewState} = start_loaded(Instance, StartOpts, State),
                    lager:debug("FSM started, ref=~p.", [FsmRef]),
                    {online, NewState};
                fail ->
                    % TODO: Suspend
                    lager:notice("Suspending FSM on startup, give up restarting, ref=~p, id=~p.", [FsmRef, InstId]),
                    {offline, InstId}
            end;
        {ok, #instance{id = InstId, status = Status}} ->
            lager:notice("FSM going to offline during startup, ref=~p, status=~p.", [FsmRef, Status]),
            {offline, InstId}
    end.


%%
%%  Starts already loaded instance.
%%
start_loaded(Instance, StartOpts, State) ->
    #instance{
        id = InstId,
        group = Group,
        name = Name,
        module = Module,
        transitions = Transitions
    } = Instance,
    #state{
        registry = Registry
    } = State,

    undefined = erlang:put('eproc_fsm$id', InstId),
    undefined = erlang:put('eproc_fsm$group', Group),
    undefined = erlang:put('eproc_fsm$name', Name),

    ok = register_online(Instance, Registry, StartOpts),

    {ok, LastTrnNr, LastSName, LastSData, LastAttrId, ActiveAttrs} = case Transitions of
        []           -> create_state(Instance);
        [Transition] -> reload_state(Instance, Transition)
    end,

    {ok, UpgradedSName, UpgradedSData} = upgrade_state(Instance, LastSName, LastSData),
    {ok, AttrState} = eproc_fsm_attr:init(UpgradedSName, LastAttrId, ActiveAttrs),
    {ok, LastSDataWithRT, RTField, RTDefault} = call_init_runtime(UpgradedSName, UpgradedSData, Module),

    NewState = State#state{
        inst_id = InstId,
        module  = Module,
        sname   = UpgradedSName,
        sdata   = LastSDataWithRT,
        rt_field    = RTField,
        rt_default  = RTDefault,
        trn_nr  = LastTrnNr,
        attrs   = AttrState
    },
    {ok, NewState}.


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
register_online(#instance{id = InstId, name = Name}, Registry, StartOpts) ->
    case proplists:get_value(register, StartOpts) of
        undefined -> ok;
        none -> ok;
        id   -> eproc_registry:register_fsm(Registry, InstId, [{inst, InstId}]);
        name -> eproc_registry:register_fsm(Registry, InstId, [{name, Name}]);
        both -> eproc_registry:register_fsm(Registry, InstId, [{inst, InstId}, {name, Name}])
    end.


%%
%%  Initialize current state for the first transition.
%%
create_state(Instance) ->
    #instance{
        init = InitSData
    } = Instance,
    {ok, 0, [], InitSData, 0, []}.


%%
%%  Prepare a state after normal restart or resume with not updated state.
%%
reload_state(_Instance, Transition) ->
    #transition{
        number = LastTrnNr,
        sname  = LastSName,
        sdata  = LastSData,
        attr_last_id = LastAttrId,
        attrs_active = AttrsActive
    } = Transition,
    {ok, LastTrnNr, LastSName, LastSData, LastAttrId, AttrsActive}.


%%
%%  Perform state upgrade on code change or state reload from db.
%%
upgrade_state(#instance{module = Module}, SName, SData) ->
    case Module:code_change(state, SName, SData, undefined) of
        {ok, NextSName, NewSData} ->
            {ok, NextSName, NewSData};
        {ok, NextSName, NewSData, _RTField} ->
            lager:warning("Runtime field is returned from the code_change/4, but it will be overriden in init/2."),
            {ok, NextSName, NewSData}
    end.


%%
%%  Perform a state transition.
%%
perform_transition(Trigger, InitAttrActions, State) ->
    #state{
        inst_id = InstId,
        module = Module,
        sname = SName,
        sdata = SData,
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
        sync = TriggerSync,
        reply_fun = From,
        src_arg = TriggerSrcArg
    } = Trigger,

    erlang:put('eproc_fsm$messages', []),
    erlang:put('eproc_fsm$reply', noreply),
    TrnNr = LastTrnNr + 1,
    TrnStart = erlang:now(),
    {ok, TrnAttrs} = eproc_fsm_attr:transition_start(InstId, TrnNr, SName, Attrs),

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
    true = is_next_state_valid(NewSName),

    ExplicitReply = erlang:erase('eproc_fsm$reply'),
    {ok, Reply} = case {TriggerSync, TransitionReply, ExplicitReply} of
        {true,  {reply, TR}, noreply    } -> {ok, {reply, TR}};
        {true,  noreply,     {reply, ER}} -> {ok, {reply, ER}};
        {false, noreply,     noreply    } -> {ok, noreply}
    end,

    {ProcAction, SDataAfterTrn} = case TrnMode of
        same ->
            {cont, NewSData};
        next ->
            {ok, SDataAfterExit} = perform_exit(SName, NewSName, NewSData, State),
            {ok, SDataAfterEntry} = perform_entry(SName, NewSName, SDataAfterExit, State),
            {cont, SDataAfterEntry};
        final ->
            {ok, SDataAfterExit} = perform_exit(SName, NewSName, NewSData, State),
            {stop, SDataAfterExit}
    end,

    {ok, AttrActions, LastAttrId, NewAttrs} = eproc_fsm_attr:transition_end(InstId, TrnNr, NewSName, TrnAttrs),
    TrnEnd = erlang:now(),

    %%  Collect all messages.
    {RegisteredMsgs, RegisteredMsgRefs, InstId, TrnNr, _LastMsgNr} = lists:foldr(
        fun registered_messages/2,
        {[], [], InstId, TrnNr, 2},
        erlang:erase('eproc_fsm$messages')
    ),
    RequestMsgId = {InstId, TrnNr, 0},
    RequestMsgRef = #msg_ref{id = RequestMsgId, peer = TriggerSrc},
    RequestMsg = #message{
        id       = RequestMsgId,
        sender   = TriggerSrc,
        receiver = {inst, InstId},
        resp_to  = undefined,
        date     = TrnStart,
        body     = TriggerMsg
    },
    {ResponseMsgRef, TransitionMsgs} = case Reply of
        noreply ->
            {undefined, [RequestMsg | RegisteredMsgs]};
        {reply, ReplyMsg} ->
            ResponseMsgId = {InstId, TrnNr, 1},
            ResponseRef = #msg_ref{id = ResponseMsgId, peer = TriggerSrc},
            ResponseMsg = #message{
                id       = ResponseMsgId,
                sender   = {inst, InstId},
                receiver = TriggerSrc,
                resp_to  = RequestMsgId,
                date     = TrnEnd,
                body     = ReplyMsg
            },
            {ResponseRef, [RequestMsg, ResponseMsg | RegisteredMsgs]}
    end,

    %%  Save transition.
    InstStatus = case ProcAction of
        cont -> running;
        stop -> done
    end,
    Transition = #transition{
        inst_id = InstId,
        number = TrnNr,
        sname = NewSName,
        sdata = cleanup_runtime_data(SDataAfterTrn, RuntimeField, RuntimeDefault),
        timestamp = TrnStart,
        duration = timer:now_diff(TrnEnd, TrnStart),
        trigger_type = TriggerType,
        trigger_msg  = RequestMsgRef,
        trigger_resp = ResponseMsgRef,
        trn_messages = RegisteredMsgRefs,
        attr_last_id = LastAttrId,
        attr_actions = InitAttrActions ++ AttrActions,
        attrs_active = undefined,
        inst_status  = InstStatus,
        inst_suspend = undefined
    },
    {ok, InstId, TrnNr} = eproc_store:add_transition(Store, Transition, TransitionMsgs),

    RefForReg = fun
        (undefined) -> undefined;
        (#msg_ref{id = I}) -> {ref, I}
    end,
    {ok, _} = register_message(TriggerSrc, {inst, InstId}, RefForReg(RequestMsgRef), RefForReg(ResponseMsgRef)),

    %% Ok, save changes in the state.
    NewState = State#state{
        sname = NewSName,
        sdata = SDataAfterTrn,
        trn_nr = TrnNr,
        attrs = NewAttrs
    },
    {ProcAction, TransitionReply, NewState}.


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
perform_entry(PrevSName, NextSName, SData, #state{module = Module}) ->
    case Module:handle_state(NextSName, {entry, PrevSName}, SData) of
        {ok, NewSData} ->
            {ok, NewSData}
    end.


%%
%%  Resolves messages and references that were registered during
%%  particular transition.
%%
registered_messages(
        {msg_reg, MsgDst, {ref, MsgId}, undefined},
        {Msgs, Refs, InstId, TrnNr, MsgNr}
        ) ->
    NewRef = #msg_ref{id = MsgId, peer = MsgDst},
    {Msgs, [NewRef | Refs], InstId, TrnNr, MsgNr};

registered_messages(
        {msg_reg, MsgDst, {ref, MsgReqId}, {ref, MsgResId}},
        {Msgs, Refs, InstId, TrnNr, MsgNr}
        ) ->
    NewReqRef = #msg_ref{id = MsgReqId, peer = MsgDst},
    NewResRef = #msg_ref{id = MsgResId, peer = MsgDst},
    {Msgs, [NewReqRef, NewResRef | Refs], InstId, TrnNr, MsgNr};

registered_messages(
        {msg_reg, MsgDst, {msg, MsgBody, MsgDate}, undefined},
        {Msgs, Refs, InstId, TrnNr, MsgNr}
        ) ->
    MsgId = {InstId, TrnNr, MsgNr},
    NewRef = #msg_ref{id = MsgId, peer = MsgDst},
    NewMsg = #message{
        id       = MsgId,
        sender   = {inst, InstId},
        receiver = MsgDst,
        resp_to  = undefined,
        date     = MsgDate,
        body     = MsgBody
    },
    {[NewMsg | Msgs], [NewRef | Refs], InstId, TrnNr, MsgNr + 1};

registered_messages(
        {msg_reg, MsgDst, {msg, MsgReqBody, MsgReqDate}, {msg, MsgResBody, MsgResDate}},
        {Msgs, Refs, InstId, TrnNr, MsgNr}
        ) ->
    MsgReqId = {InstId, TrnNr, MsgNr},
    MsgResId = {InstId, TrnNr, MsgNr + 1},
    NewReqRef = #msg_ref{id = MsgReqId, peer = MsgDst},
    NewResRef = #msg_ref{id = MsgResId, peer = MsgDst},
    NewReqMsg = #message{
        id       = MsgReqId,
        sender   = {inst, InstId},
        receiver = MsgDst,
        resp_to  = undefined,
        date     = MsgReqDate,
        body     = MsgReqBody
    },
    NewResMsg = #message{
        id       = MsgResId,
        sender   = MsgDst,
        receiver = {inst, InstId},
        resp_to  = MsgReqId,
        date     = MsgResDate,
        body     = MsgResBody
    },
    {[NewReqMsg, NewResMsg | Msgs], [NewReqRef, NewResRef | Refs], InstId, TrnNr, MsgNr + 2}.


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
        N =:= start_spec;
        N =:= max_transitions;
        N =:= max_errors;
        N =:= max_sent_msgs
        ->
    {[Prop | Create], Start, Send, Common, Unknown};

split_options(Prop = {N, _}, {Create, Start, Send, Common, Unknown}) when
        N =:= restart;
        N =:= register
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
    {ok, FsmRef} = create(Module, Args, AllCreateOpts),

    Registry = resolve_registry(CommonOpts),
    AllSendOpts = lists:append(SendOpts, CommonOpts),
    {ok, StartSpec} = resolve_start_spec(CreateOpts),
    {ok, NewFsmRef} = eproc_registry:make_new_fsm_ref(Registry, FsmRef, StartSpec),
    {ok, FsmRef, NewFsmRef, AllSendOpts}.



%% =============================================================================
%%  Unit tests for private functions.
%% =============================================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%%
%%  Unit tests for resolve_event_src/1.
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
%%  Unit tests for split_options/1.
%%
split_options_test_() -> [
    ?_assertMatch(
        {ok, [], [], [], [], []},
        split_options([])
    ),
    ?_assertMatch(
        {ok,
            [{group, x}, {name, x}, {start_spec, x}, {max_transitions, x}, {max_errors, x}, {max_sent_msgs, x}],
            [{restart, x}, {register, x}],
            [{source, x}],
            [{timeout, x}, {store, x}, {registry, x}, {user, x}],
            [{some, y}]
        },
        split_options([
            {group, x}, {name, x}, {start_spec, x}, {max_transitions, x}, {max_errors, x}, {max_sent_msgs, x},
            {restart, x}, {register, x}, {source, x}, {timeout, x}, {store, x}, {registry, x}, {user, x}, {some, y}
        ])
    )].

-endif.


