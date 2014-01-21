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
%%    * Process configuration is passed as a separate argument to the fsm. TODO: WTF?
%%    * Has support for state entry and exit actions.
%%      State entry action is convenient for setting up timers and keys.
%%    * Has support for scopes. The scopes can be used to manage timers and keys.
%%    * Supports automatic state persistence.
%%
%%  It is recomended to name version explicitly when defining state. It can be done as follows:
%%
%%      -record(state, {
%%          version = 1,
%%          ...
%%      }).
%%
%%
%%  How `eproc_fsm` callbacks are invoked in different scenarios
%%  ------------------------------------------------------------
%%
%%  New FSM created, started and an initial event received
%%  :
%%        * `init(Args)`
%%        * `init(InitStateName, StateData)`
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
%%  Implementation details
%%  ----------------------
%%
%%  Several states are maintained during lifeycle of the process:
%%    * `starting`  - while FSM initializes itself asynchronously.
%%    * `running`   - when the FSM is running.
%%    * `suspended` - when the FSM is suspended paused by an administrator of marked automatically as faulty.
%%
%%  FSM can reach the following terminal states:    TODO: Map it with the UML diagram.
%%    * `{done, success}` - when the FSM was completed successfully.
%%    * `{done, failure}` - when the FSM was completed by the callback module returning special response TODO.
%%    * `{term, killed}`  - when the FSM was killed in the `running` or the `paused` state.
%%    * `{term, failed}`  - when the FSM was terminated in the `faulty` state.
%%
%%
-module(eproc_fsm).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).

%%
%%  Client-side functions.
%%
-export([
    create/3, start_link/3, start_link/2, await/2, id/0, group/0, name/0,
    send_create_event/4, sync_send_create_event/4, send_event/2,
    sync_send_event/3, sync_send_event/2,
    kill/2, suspend/2, resume/2, set_state/4
]).

%%
%%  Process-side functions.
%%
-export([
    reply/2
]).


%%
%%  APIs for related eproc modules.
%%
-export([
    state_in_scope/2,
    register_message/2
]).


%%
%%  Callbacks for `gen_server`.
%%
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%
%%  Type exports.
%%
-export_type([name/0, id/0, group/0]).

%%
%%  Internal things...
%%
-include("eproc.hrl").
-define(DEFAULT_TIMEOUT, 10000).

%%
%%  Unit tests.
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.



-type name() :: {via, Registry :: module(), InstId :: inst_id()}.
-opaque id()  :: integer().
-opaque group() :: integer().

-type timer_name() :: term().

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
%%      `{sync, From, Message}`
%%      :   indicates an event `Message` sent by `From` to the FSM synchronously.
%%      `{timer, Timer, Message}`
%%      :   indicates a time event `Message`, that was fired by a `Timer`.
%%      `{exit, NextStateName}`
%%      :   indicates that a transition was made from the `StateName` to the
%%          `NextStateName` and now we are exiting the `StateName`.
%%      `{entry, PrevStateName}`
%%      :   indicates that a transition was made from the `PrevStateName` to the
%%          `StateName` and now we are entering the `StateName`. A handler for
%%          state entry is a good place to set up timers that shouls be valid in
%%          that state.
%%
%%  `StateData`
%%  :   contains internal state of the FSM.
%%
%%  If the function was invoked with `{event, Message}` or `{timer, Timer, Message}`,
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
                       {timer, Timer, Message} |
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
        From    :: term(),
        Timer   :: timer_name(),
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
%%  The state changes will be indicated in the following cases: TODO: Review, add RuntimeField.
%%
%%    * On process startup (when a persistent FSM becomes online).
%%    * On FSM resume (after being suspended).
%%
%%  This function will be invoked on hot code upgrade, as usual. In this case
%%  the function will be invoked as described in `gen_fsm`.
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
%%      options used by this module (listed bellows) as well as unknown
%%      options that can be used as a metadata for the FSM.
%%
%%  On success, this function returns instance id of the newly created FSM.
%%  It can be used then to start the instance and to reference it.
%%
%%  Options known by this function:
%%
%%  `{group, group() | new}`
%%  :   Its a group ID to which the FSM should be assigned or atom `new`
%%      indicating that new group should be created for this FSM.
%%  `{name, Name}`
%%  :   Name of the FSM. It uniquelly identifies the FSM.
%%      Name is valid for the entire FSM lifecycle, including
%%      the `completed` state.
%%  `{store, store_ref()}`
%%  :   Reference of a store, in which the instance should be created.
%%      If not provided, default store is used.
%%
%%  TODO: Add various runtime limits here.
%%  TODO: Add StartMFA.
%%
-spec create(
        Module  :: module(),
        Args    :: term(),
        Options :: proplist()
    ) ->
        {ok, fsm_ref()} |
        {error, already_created}.

create(Module, Args, Options) ->
    {KnownOpts, UnknownOpts} = proplists:split(Options, [group, name, store]),
    {ok, InstId} = handle_create(Module, Args, lists:append(KnownOpts), UnknownOpts),
    {ok, {inst, InstId}}.


%%
%%  Start previously created (using `create/3`) `eproc_fsm` instance.
%%
%%  As part of initialization procedure, the FSM registers itself to the
%%  registry. Registration by InstId is done synchronously and registrations
%%  by Name and Keys are done asynchronously. One can use `await/2` to
%%  synchronize with the FSM. Name is registered after all keys are registered.
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
%%  `{restart_delay, integer()}`        TODO: Implement it.
%%  :   specifies a delay, that is made on each process restart. The default is 1000 ms.
%%      The delay is make on each crash, during an abnormal termination of a process.
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
    {ok, StartOptions, ProcessOptions} = resolve_start_link_opts(Options),
    gen_server:start_link(FsmName, ?MODULE, {FsmRef, StartOptions}, ProcessOptions).


%%
%%  Same as `start_link/3`, just without FsmName parameter.
%%
-spec start_link(
        FsmRef      :: fsm_ref(),
        Options     :: proplist()
    ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(FsmRef, Options) ->
    {ok, StartOptions, ProcessOptions} = resolve_start_link_opts(Options),
    gen_server:start_link(?MODULE, {FsmRef, StartOptions}, ProcessOptions).


%%
%%  Awaits for the specified FSM by an instance id, a name or a key.
%%
%%  This function should be considered as a low-level API. The functions
%%  `send_create_event/*` and `sync_send_create_event/*` should be used
%%  in an ordinary case.
%%
%%  Parameters:
%%
%%  `FsmRef`
%%  :   An id, a name or a key to await.
%%  `Timeout`
%%  :   Number of milliseconds to await.
%%
-spec await(
        FsmRef :: fsm_ref(),
        Timeout :: integer()
        ) ->
        ok | {error, timeout} | {error, term()}.

await(FsmRef, Timeout) ->
    eproc_registry:await(undefined, FsmRef, Timeout).


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
%%  Use this function in the `eproc_fsm` callback module implementation to start
%%  the FSM asynchronously.
%%
%%  This function awaits for the FSM to be initialized. I.e. it is guaranteed,
%%  that the name and the keys, if were provided, are registered before this
%%  function exits. Nevertheless, the initial message is processes asynchronously.
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
%%      from the `initial` state.
%%  `From`
%%  :   is passed to the `send_event/2` function (see its description for more details).
%%  `Options`
%%  :   Options, that can be specified when starting the FSM. They are listed bellow.
%%
%%  Available options:
%%
%%  `{timeout, Timeout}`
%%  :   Timeout to await for the FSM to be started.
%%  `{group, Group}`
%%  :   can be used to prevent derining group from the parent process
%%      or to specify group for a process created based on external message.
%%      For more details see description of `create/3` function.
%%  All options handled by `create/3`
%%  :   All the options are passed to the `create/3` function.
%%
%%  Group is derived from the `From` parameter unless it was explicitly specified
%%  in the `Options` parameter. In that case, the group will be ingerited from the
%%  syncer FSM or new group will be created if mesage is from an external source.
%%
-spec send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Options :: proplist()
        ) ->
        {ok, inst_id()} |
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

send_create_event(Module, Args, Event, Options) ->
    Timeout = resolve_timeout(Options),
    {ok, InstId} = create_start_link(Module, Args, Options, Timeout),
    % TODO: The following is the second remote sync in the case of riak.
    %       Await - is probably the third. Move it somehow to the remote part.
    ok = send_event({inst, InstId}, Event),
    ok = await_for_created(Options, Timeout),
    {ok, InstId}.



%%
%%  Use this function in the `eproc_fsm` callback module implementation to start
%%  the FSM chronously. All the parameters and the options are the same as for the
%%  `send_create_event/5` function (see its description for more details).
%%
-spec sync_send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Options :: proplist()
    ) ->
        {ok, inst_id(), Reply :: term()} |
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

sync_send_create_event(Module, Args, Event, Options) ->
    Timeout = resolve_timeout(Options),
    {ok, InstId} = create_start_link(Module, Args, Options, Timeout),
    % TODO: The following is the second remote sync in the case of riak.
    %       Move it somehow to the remote part.
    {ok, Response} = case proplists:is_defined(timeout, Options) of
        false -> sync_send_event({inst, InstId}, Event);
        true  -> sync_send_event({inst, InstId}, Event, Timeout)
    end,
    {ok, InstId, Response}.


%%
%%  Sends an event to the FSM asynchronously.
%%
send_event(Name, Event) ->
    From = resolve_calling_fsm(),
    gen_server:cast(Name, {'eproc_fsm$send_event', Event, From}).


%%
%%  Sends an event to the FSM synchronously.
%%
sync_send_event(Name, Event) ->
    From = resolve_calling_fsm(),
    gen_server:call(Name, {'eproc_fsm$sync_send_event', Event, From}).


%%
%%
%%
sync_send_event(Name, Event, Timeout) ->
    From = resolve_calling_fsm(),
    gen_server:call(Name, {'eproc_fsm$sync_send_event', Event, From}, Timeout).


%%
%%
%%
kill(Name, Reason) ->
    gen_server:cast(Name, {'eproc_fsm$kill', Reason}).


%%
%%
%%
suspend(Name, Reason) ->
    gen_server:call(Name, {'eproc_fsm$suspend', Reason}).


%%
%%
%%
resume(Name, Reason) ->
    gen_server:call(Name, {'eproc_fsm$resume', Reason}).


%%
%%
%%
set_state(Name, NewStateName, NewStateData, Reason) ->
    % TODO: Make it offline.
    gen_server:call(Name, {'eproc_fsm$set_state', NewStateName, NewStateData, Reason}).


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
    gen_server:reply(To, Reply).


%%
%%  TODO: Implement.
%%  This function is used by modules sending outgoing messages from the FSM.
%%
register_message(Sender, Event) ->
    ok.



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
    store       :: store_ref()      %% A store reference.
}).



%% =============================================================================
%%  Callbacks for `gen_server`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({FsmRef, StartOptions}) ->
    State = #state{
        store    = resolve_store(StartOptions),
        registry = resolve_registry(StartOptions)
    },
    self() ! {'eproc_fsm$start', FsmRef, StartOptions},
    {ok, State}.


%%
%%  TODO:
%%
handle_call(_Event, _From, State) ->
    {reply, not_implemented, State}.


%%
%%  TODO:
%%
handle_cast(_Event, State) ->
    {noreply, State}.


%%
%%  Asynchronous FSM initialization.
%%
handle_info({'eproc_fsm$start', FsmRef, StartOptions}, State) ->
    case handle_start(FsmRef, StartOptions, State) of
        {online, NewState} ->
            {noreply, NewState};
        {offline, InstId} ->
            eproc_restart:cleanup({?MODULE, InstId}),
            {stop, normal, State}
    end;

%%
%%  Handles FSM attribute events.
%%
handle_info(Event, State = #state{attrs = Attrs}) ->
    case eproc_fsm_attr:event(Event, Attrs) of
        {handled, NewAttrs} ->
            {noreply, State#state{attrs = NewAttrs}};
        {trigger, NewAttrs, Trigger, AttrAction} ->
            NewState = State#state{attrs = NewAttrs},
            % TODO: do a transition.
            {noreply, NewState};
        unknown ->
            lager:warning("Ignoring unknown event ~p", Event),
            {noreply, State}
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
%%  Create and start FSM.
%%
create_start_link(Module, Args, Options, Timeout) ->
    OptsWithGroup = resolve_create_opts(group, Options),
    {ok, InstId} = create(Module, Args, OptsWithGroup),
    ok = eproc_registry:start_instance(undefined, InstId, [{timeout, Timeout}]),
    {ok, InstId}.


%%
%%  Extracts timeout from the options.
%%
resolve_timeout(Options) ->
    proplists:get_value(timeout, Options, ?DEFAULT_TIMEOUT).


%%
%%
%%
resolve_start_link_opts(Options) ->
    {StartOptions, ProcessOptions} = proplists:split(Options, [restart_delay, register]),
    {ok, lists:append(StartOptions), ProcessOptions}.


%%
%%  Resolves FSM create options.
%%
%%    * Group is taken from the context of the calling process
%%      if not provided in the options explicitly. If the calling
%%      process is not FSM, new group will be created.
%%
resolve_create_opts(group, CreateOptions) ->
    case proplists:is_defined(group, CreateOptions) of
        true -> [];
        false ->
            case group() of
                {ok, Group} -> [{group, Group}];
                {error, not_fsm} -> [{group, new}]
            end
    end.


%%
%%  Returns either instance id or undefined, if the current process
%%  is not `eproc_fsm` process.
%%
resolve_calling_fsm() ->
    case id() of
        {ok, InstId}     -> InstId;
        {error, not_fsm} -> undefined
    end.


%%
%%
%%
resolve_store(StartOptions) ->
    case proplists:get_value(store, StartOptions) of
        undefined ->
            {ok, Store} = eproc_store:ref(),
            Store;
        Store ->
            Store
    end.


%%
%%
%%
resolve_registry(StartOptions) ->
    case proplists:get_value(store, StartOptions) of
        undefined ->
            case eproc_registry:ref() of
                {ok, Registry} ->
                    Registry;
                undefined ->
                    undefined
            end;
        Registry ->
            Registry
    end.


%%
%%  Awaits for the newly created FSM.
%%
await_for_created(Options, Timeout) ->
    Name = proplists:get_value(name, Options, undefined),
    Keys = proplists:get_value(keys, Options, []),
    case {Name, lists:reverse(Keys)} of
        {undefined, []}         -> ok;
        {undefined, [Key | _]}  -> await({key, Key}, Timeout);
        {Name, _}               -> await({name, Name}, Timeout)
    end.


%%
%%  Creates new instance, initializes its initial state.
%%
handle_create(Module, Args, CreateOpts, CustomOpts) ->
    Group = proplists:get_value(group, CreateOpts, new),
    Name  = proplists:get_value(name,  CreateOpts, undefined),
    Store = proplists:get_value(store, CreateOpts, undefined),
    {ok, InitSData} = call_init_persistent(Module, Args),
    Instance = #instance{
        id          = undefined,
        group       = Group,
        name        = Name,
        module      = Module,
        args        = Args,
        opts        = CustomOpts,
        init        = InitSData,
        status      = running,
        created     = eproc:now(),
        terminated  = undefined,
        archived    = undefined,
        transitions = undefined
    },
    {ok, _InstId} = eproc_store:add_instance(Store, Instance).


%%
%%  Loads the instance and starts it if needed.
%%
handle_start(FsmRef, StartOptions, State = #state{store = Store}) ->
    case eproc_store:load_instance(Store, FsmRef) of
        {ok, Instance = #instance{id = InstId, status = running}} ->
            case eproc_restart:restarted({?MODULE, InstId}, []) of
                ok ->
                    {ok, NewState} = start_loaded(Instance, StartOptions, State),
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
start_loaded(Instance, StartOptions, State) ->
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

    ok = register_online(Instance, Registry, StartOptions),

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
register_online(#instance{id = InstId, name = Name}, Registry, StartOptions) ->
    case proplists:get_value(register, StartOptions) of
        undefined ->
            ok;
        id ->
            eproc_registry:register_inst(Registry, InstId);
        name ->
            eproc_registry:register_name(Registry, InstId, Name);
        both ->
            eproc_registry:register_inst(Registry, InstId),
            eproc_registry:register_name(Registry, InstId, Name)
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
reload_state(Instance, Transition) ->
    #transition{
        number = LastTrnNr,
        sname  = LastSName,
        sdata  = LastSData,
        attr_last_id = LastAttrId,
        attrs_active = AttrsActive
    } = Transition,
    {ok, LastTrnNr, LastSName, LastSData, LastAttrId, AttrsActive}.


%%
%%  Prepare a state after resume wuth state updated externally.
%%  TODO: Implement.
%%
%update_state(Instance, Transition, Update, Store) ->
%    #instance{
%        id = InstId
%    } = Instance,
%    #transition{
%        number = LastTrnNr,
%        active = Attrs
%    } = Transition,
%    #inst_suspension{
%        upd_sname = UpdSName,
%        upd_sdata = UpdSData
%    } = Update,
%    NewTrnNr = LastTrnNr + 1,
%    NewTransition = #transition{
%        inst_id = InstId,
%        number = NewTrnNr,
%        sname = UpdSName,
%        sdata = UpdSData,
%        timestamp = eproc:now(),
%        duration = 0,
%        trigger = todo % TODO,
%    },
%    {ok, NewTrnNr} = eproc_store:add_transition(Store, NewTransition),
%    {ok, UpgradedSName, UpgradedSData} = upgrade_state(Instance, UpdSName, UpdSData),
%    {ok, NewTrnNr, UpgradedSName, UpgradedSData, Attrs}.


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
%%  Checks, if a state is in specified scope.
%%
state_in_scope(State, Scope) when State =:= Scope; Scope =:= []; Scope =:= '_' ->
    true;

state_in_scope([BaseState | SubStates], [BaseScope | SubScopes]) when BaseState =:= BaseScope; BaseScope =:= '_' ->
    state_in_scope(SubStates, SubScopes);

state_in_scope([BaseState | SubStates], [BaseScope | SubScopes]) when element(1, BaseState) =:= BaseScope ->
    state_in_scope(SubStates, SubScopes);

state_in_scope([BaseState | _SubStates], [BaseScope | _SubScopes]) when is_tuple(BaseState), is_tuple(BaseScope) ->
    [StateName | StateRegions] = tuple_to_list(BaseState),
    [ScopeName | ScopeRegions] = tuple_to_list(BaseScope),
    RegionCheck = fun
        (_, false) -> false;
        ({St, Sc}, true) -> state_in_scope(St, Sc)
    end,
    NamesEqual = StateName =:= ScopeName,
    SizesEqual = tuple_size(BaseState) =:= tuple_size(BaseScope),
    case NamesEqual and SizesEqual of
        true -> lists:foldl(RegionCheck, true, lists:zip(StateRegions, ScopeRegions));
        false -> false
    end;

state_in_scope(_State, _Scope) ->
    false.



%% =============================================================================
%%  Unit tests for internal functions.
%% =============================================================================

-ifdef(TEST).
-endif.
