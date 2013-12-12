%/--------------------------------------------------------------------
%| Copyright 2013 Robus, Ltd.
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
%%    * Callback `Module:handle_state/4` is used instead of `Module:StateName/2-3`.
%%    * Process configuration is passed as a separate argument to the fsm. TODO: WTF?
%%    * Has support for state entry and exit actions.
%%    * Has support for scopes. The scopes can be used to manage timers and keys.
%%    * Supports automatic state persistence.
%%
%%  Several states are maintained during lifeycle of the process:
%%    * `initializing` - while FSM initializes itself asynchronously.
%%    * `running`   - when the FSM is running.
%%    * `paused`    - when the FSM is suspended (paused) by an administrator.
%%    * `faulty'    - when the FSM is suspended because of errors.
%%
%%  FSM can reach the following terminal states:    TODO: Map it with the UML diagram.
%%    * `{done, success}` - when the FSM was completed successfully.
%%    * `{done, failure}` - when the FSM was completed by the callback module returning special response TODO.
%%    * `{term, killed}`  - when the FSM was killed in the `running` or the `paused` state.
%%    * `{term, failed}`  - when the FSM was terminated in the `faulty` state.
%%
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
%%  New FSM created
%%  :
%%        * `init(Args, InstRef)`
%%        * `init(InitStateName, StateData, InstRef)`
%%        * `handle_state(StateName, event, Event, StateData, InstRef)`
%%        * `handle_state(NewStateName, entry, InitStateName, StateData, InstRef)`
%%
%%  FSM process terminated
%%  :
%%        * `terminate(Reason, StateName, StateData, InstRef)`
%%
%%  FSM is restarted
%%  :
%%        * `init(StateName, StateData, InstRef)`
%%        * `code_change(state, StateName, StateData, undefined)`
%%
%%  FSM upgraded in run-time
%%  :
%%        * `code_change(OldVsn, StateName, StateData, Extra)`
%%
%%  Event initiated a transition (`next_state`)
%%  :
%%        * `handle_state(StateName, event, Event, StateData, InstRef)`
%%        * `handle_state(StateName, exit, NewStateName, StateData, InstRef)`
%%        * `handle_state(NewStateName, entry, StateName, StateData, InstRef)`
%%
%%  Event with no transition (`same_state`)
%%  :
%%        * `handle_state(StateName, event, Event, StateData, InstRef)`
%%
%%  Event initiated a termination (`final_state`)
%%  :
%%        * `handle_state(StateName, event, Event, StateData, InstRef)`
%%        * `handle_state(StateName, exit, FinalStateName, StateData, InstRef)`
%%
%%
-module(eproc_fsm).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).

%%
%%  Client-side functions.
%%
-export([
    create/3, start_link/2, await/2,
    send_create_event/5, sync_send_create_event/5,
    send_event/3, send_event/2, sync_send_event/4, sync_send_event/3,
    kill/2, suspend/2, resume/2, set_state/4
]).

%%
%%  Process-side functions.
%%
-export([
    reply/2, add_key_sync/3, add_key/3,
    add_timer/5, add_timer/4, cancel_timer/2,
    add_prop/3, set_name/2
]).

%%
%%  Callbacks for `gen_fsm`.
%%
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([running/2, running/3, paused/2, paused/3, faulty/2, faulty/3]).

%%
%%  Type exports.
%%
-export_type([name/0, id/0, ref/0, group/0]).

%%
%%  Internal things...
%%
-include("eproc.hrl").
-define(DEFAULT_TIMEOUT, 10000).


%%
%%  Structure, passed to all callbacks, to be used to indicate process.
%%
-record(inst_ref, {
    id      :: inst_id(),
    group   :: inst_group()
}).


-record(inst_key, { % TODO
    key,
    scope
}).
-record(inst_timer, { % TODO
    from,
    duration,
    event
}).
-record(inst_prop, { % TODO
    name,
    value
}).


-type name() :: {via, Registry :: module(), InstId :: inst_id()}.
-opaque id()  :: integer().
-opaque ref() :: #inst_ref{}.
-opaque group() :: integer().
-type prop_elem() :: list() | binary() | integer().
-type event_src() :: undefined | #inst_ref{} | term().

%%
%%  An event, received by the FSM.
%%
-type state_event() :: term().

%%
%%  State name
%%  TODO: Describe its structure.
%%
-type state_name() :: list().

%%
%%  TODO: Describe.
%%
-type state_scope() :: state_name().

%%
%%  Internal state of the callback module. The state is considered
%%  opaque by the `eproc_fsm`, but its usually an instance of the
%%  #state{} record in the user module.
%%
-type state_data() :: term().

%%
%%  TODO: Describe.
%%
-type state_action() ::
    {name, Name :: term()} |
    {key, Key :: term(), Scope :: state_scope()} |  % Options are left as undocumented feature.
    {prop, PropName :: prop_elem(), PropValue :: prop_elem()} |
    {timer, TimerName :: term(), After :: integer(), Event :: state_event(), Scope :: state_scope()} |
    {timer, TimerName :: term(), cancel}.

%%
%%  TODO: Describe.
%%
-type state_phase() :: event | entry | exit.


%%
%%  Internal state of the `eproc_fsm`.
%%
-record(state, {
    inst_id,
    module,
    sname,
    sdata,
    trn_id,
    keys,
    props,
    timers,
    registry,
    store,
    msg         %% The currently processed message. TODO: Do we need it? For terminate/2?
}).



%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  Invoked when initializing the FSM. This fuction is invoked only on first
%%  initialization. I.e. it is not invoked on restarts.
%%
%%  Parameters:
%%
%%  `Args`
%%  :   is the value passed as the `Args` parameter to the `create/3`,
%%      `send_create_event/5` or `sync_send_create_event/5` function.
%%  `InstRef`
%%  :   Instance reference. It can be used to send messages via connectors
%%      (channels) and to access other information. InstRef identifies
%%      the FSM instance and its state.
%%
%%  The function needs to return `StateData` - state data of the process
%%  and optionally state name and actions.
%%
%%  If `StateName` is not provided, the state name `initial` is assumed.
%%  Actions can be used here to set FSM name, keys, properties and timers.
%%
-callback init(
        Args    :: term(),
        InstRef :: inst_ref()
    ) ->
    {ok, StateData :: state_data()} |
    {ok, StateName :: state_name(), StateData :: state_data()} |
    {ok, StateName :: state_name(), StateData :: state_data(), Actions :: [state_action()]}.

%%
%%  This function is invoked on each (re)start of the FSM. On the first start
%%  this callback is invoked after the `init/2` callback.
%%
%%  In this function the FSM can initialize its run-time resources: start or link to
%%  processes, etc.
%%
%%  Parameters:
%%      `StateName`
%%      :   is the state name loaded from the persistent store or returned
%%          by the `init/2` callback, if initialization is performed for a new instance.
%%      `StateData`
%%      :   is the corresponding state data.
%%      `InstRef`
%%      :   has the same meaning, as in the `init/2` callback.
%%
%%  The function should return state data and state name. They both can be transformed
%%  in this function. Nevertheless, the transformed state will only be persisted on the
%%  next transition.
%%
-callback init(
        StateName   :: state_name(),
        StateData   :: state_data(),
        InstRef     :: inst_ref()
    ) ->
    {ok, StateName :: state_name(), StateData :: state_data()}.

%%
%%  This function handles events coming to the FSM. It is also used
%%  to handle state entries and exits.
%%
-callback handle_state(
        StateName   :: state_name(),
        StatePhase  :: state_phase(),
        StateNameOrEvent ::state_event() | state_name(),
        StateData   :: state_data(),
        InstRef     :: inst_ref()
    ) ->
    {same_state, StateData :: state_data()} |
    {same_state, StateData :: state_data(), StateActions :: [state_action()]} |
    {next_state, StateName :: state_name(), StateData :: state_data()} |
    {next_state, StateName :: state_name(), StateData :: state_data(), StateActions :: [state_action()]} |
    {final_state, StateName :: state_name(), StateData :: state_data()}.


%%
%%
%%
-callback handle_status(
        state_name(),
        state_data(),
        Query           :: atom(),
        MediaType       :: atom()
    ) ->
    {ok, MediaType :: atom(), Status :: binary() | term()} |
    {error, Reason :: term()}.


%%
%%  This callback is invoked each time after a state was loaded from the
%%  persistent store, modified by
%%
-callback state_change(
        OldStateName    :: state_name(),
        OldStateData    :: state_data(),
        InstRef         :: inst_ref()
    ) ->
    {ok, StateName :: state_name(), StateData :: state_data()}.



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
%%  Options known by this module:
%%
%%  `{group, group() | new}`
%%  :   Its a group ID to which the FSM should be assigned or atom `new`
%%      indicating that new group should be created for this FSM.
%%  `{name, Name}`
%%  :   Name of the FSM. It uniquelly identifies the FSM.
%%      Name is valid for the entire FSM lifecycle, including
%%      the `completed` state.
%%  `{keys, [Key]}`
%%  :   List of keys, that can be used to locate the FSM. Keys are
%%      not required to identify the FSM uniquelly. The keys passed to this
%%      function will be valid for all the lifetime of the FSM (i.e. scope = []).
%%  `{props, proplist()}`
%%  :   List of properties that are later converted to the normalized form
%%      `{Name :: binary(), Value :: binary()}`. The properties are similar
%%      to labels, and are to help organize the FSMs by humans.
%%
%%  TODO: Add various runtime limits here.
%%
-spec create(
        Module  :: module(),
        Args    :: term(),
        Options :: proplist()
        ) ->
        {ok, inst_id()} |
        {error, already_created}.

create(Module, Args, Options) ->
    {KnownOpts, UnknownOpts} = proplists:split(Options, [group, name, keys, props]),
    Instance = #instance{
        id = undefined,
        group = proplists:get_value(group, KnownOpts, new),
        name = proplists:get_value(name, KnownOpts, undefined), % TODO: Is it good to set it from options. Maybe init/2 is better?
        keys = proplists:get_value(keys, KnownOpts, []),        % TODO: Is it good to set it from options. Maybe init/2 is better?
        props = proplists:get_value(props, KnownOpts, []),      % TODO: Is it good to set it from options. Maybe init/2 is better?
        module = Module,
        args = Args,
        opts = UnknownOpts,
        start_time = eproc:now(),
        status = running,
        archived = undefined
    },
    eproc_store:add_instance(undefined, Instance). % TODO: Create a name and new group if needed.


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
%%  `InstId`
%%  :   InstanceId of the previously created FSM. This Id is returned by the
%%      `create/3` function.
%%  `Options'
%%  :   Runtime-level options. The options listed bellow are used by this
%%      FSM implementation and the rest are passed to the `gen_fsm:start_link/3`.
%%
%%  Options supprted by this function:
%%
%%  `{restart_delay, integer()}`    TODO: Implement it.
%%  :   specified a delay, that is made on each process restart. The default is 1000 ms.
%%      The delay is make on each crash, during an abnormal termination of a process.
%%
-spec start_link(
        InstId      :: inst_id(),
        Options     :: proplist()
        ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(InstId, Options) ->
    {KnownOpts, UnknownOpts} = proplists:split(Options, [restart_delay]),
    gen_fsm:start_link(?MODULE, {InstId, KnownOpts}, UnknownOpts).


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
%%  :   is passed to the `send_event/3` function (see its description for more details).
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
%%  caller FSM or new group will be created if mesage is from an external source.
%%
-spec send_create_event(
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        From    :: event_src(),
        Options :: proplist()
        ) ->
        {ok, inst_id()} |
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

send_create_event(Module, Args, Event, From, Options) ->
    Timeout = resolve_timeout(Options),
    {ok, InstId} = create_start_link(Module, Args, From, Options, Timeout),
    % TODO: The following is the second remote call in the case of riak.
    %       Await - is probably the third. Move it somehow to the remote part.
    ok = send_event({inst, InstId}, Event, From),
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
        From    :: event_src(),
        Options :: proplist()
        ) ->
        {ok, inst_id(), Reply :: term()} |
        {error, already_created} |
        {error, timeout} |
        {error, term()}.

sync_send_create_event(Module, Args, Event, From, Options) ->
    Timeout = resolve_timeout(Options),
    {ok, InstId} = create_start_link(Module, Args, From, Options, Timeout),
    % TODO: The following is the second remote call in the case of riak.
    %       Move it somehow to the remote part.
    {ok, Response} = case proplists:is_defined(timeout, Options) of
        false -> sync_send_event({inst, InstId}, Event, From);
        true  -> sync_send_event({inst, InstId}, Event, From, Timeout)
    end,
    {ok, InstId, Response}.


%%
%%  Sends an event to the FSM asynchronously.
%%
send_event(Name, Event, From) ->
    gen_fsm:send_event(Name, {'eproc_fsm$send_event', Event, From}).


send_event(Name, Event) ->
    send_event(Name, Event, undefined).


%%
%%  Sends an event to the FSM synchronously.
%%
sync_send_event(Name, Event, From) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$sync_send_event', Event, From}).


%%
%%
%%
sync_send_event(Name, Event, From, Timeout) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$sync_send_event', Event, From}, Timeout).


%%
%%
%%
kill(Name, Reason) ->
    gen_fsm:send_event(Name, {'eproc_fsm$kill', Reason}).


%%
%%
%%
suspend(Name, Reason) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$suspend', Reason}).


%%
%%
%%
resume(Name, Reason) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$resume', Reason}).


%%
%%
%%
set_state(Name, NewStateName, NewStateData, Reason) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$set_state', NewStateName, NewStateData, Reason}).


%%
%%  To be used by the process implementation to sent response to a synchronous
%%  request before the `handle_state/4` function completes.
%%
-spec reply(
        state_event(),
        inst_ref()
        ) -> ok.

reply(_Response, _InstRef) ->
    ok.


%%
%%
%%
add_key_sync(Key, Scope, Actions) ->
    % TODO: Register the key to the registry synchronously.
    [ {key, Key, Scope, [sync]} | Actions ].


%%
%%
%%
add_key(Key, Scope, Actions) ->
    [ {key, Key, Scope} | Actions ].


%%
%%  Creates or modifies a timer.
%%
add_timer(Name, After, Event, Scope, Actions) ->
    [ {timer, Name, After, Event, Scope} | Actions ].


%%
%%
%%
add_timer(After, Event, Scope, Actions) ->
    add_timer(undefined, After, Event, Scope, Actions).


%%
%%  Cancels a timer by name.
%%
cancel_timer(Name, Actions) ->
    [ {timer, Name, cancel} | Actions ].


%%
%%
%%
add_prop(Name, Value, Actions) ->
    [ {prop, Name, Value} | Actions].


%%
%%
%%
set_name(Name, Actions) ->
    [ {name, Name} | Actions ].



%% =============================================================================
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({InstId, _Options}) ->
    Registry = eproc:registry(),
    Store = eproc:store(),
    State = #state{
        inst_id     = InstId,
        registry    = Registry,
        store       = Store
    },
    ok = eproc_registry:register_inst(Registry, InstId),
    self() ! {'eproc_fsm$init'},
    {ok, initializing, State}.


%%
%%  Handles the `running` state.
%%
running(_Event, State) ->
    {noreply, State}.

running(_Event, _From, State) ->
    {reply, ok, State}.


%%
%%  Handles the `paused` state.
%%
paused(_Event, State) ->
    {noreply, State}.

paused(_Event, _From, State) ->
    {reply, ok, State}.


%%
%%  Handles the `faulty` state.
%%
faulty(_Event, State) ->
    {noreply, State}.

faulty(_Event, _From, State) ->
    {reply, ok, State}.


%%
%%  Not used.
%%
handle_event(_Event, StateName, StateData) ->
    {noreply, StateName, StateData}.


%%
%%  Not used.
%%
handle_sync_event(_Event, _From, StateName, StateData) ->
    {reply, not_implemented, StateName, StateData}.


%%
%%  Asynchronous FSM initialization.
%%
handle_info({'eproc_fsm$init'}, initializing, StateData) ->
    % TODO: Respect FSM state here (running, suspended).
    % TODO: Remove the `initializing` state.
    % TODO: Split this to: load and start
    % TODO: Use state `suspended` instead of `paused` and `faulty`.
    #state{
        inst_id = InstId,
        store = Store,
        registry = Registry
    } = StateData,
    {ok, Instance, Transition} = eproc_store:load_instance(Store, InstId),
    #instance{
        group = Group,
        name = InitialName,
        keys = InitialKeys,
        props = InitialProps,
        module = Module,
        args = Args
    } = Instance,
    case Transition of
        undefined ->
            %%
            %%  Initial startup.
            %%
            TrnId = undefined,
            InstRef = #inst_ref{id = InstId, group = Group},
            case Module:init(Args, InstRef) of
                {ok, SData} ->
                    SName = initial,
                    StateDataAfterInit = StateData;
                {ok, SName, SData} ->
                    StateDataAfterInit = StateData;
                {ok, SName, SData, Actions} ->
                    {ok, StateDataAfterInit} = handle_actions(Actions, StateData)
            end;
        #transition{id = TrnId, sname = SName, sdata = SData} ->
            %%
            %%  Instance was restarted.
            %%
            StateDataAfterInit = StateData
    end,
    % TODO: Load them properly
    Keys = undefined,
    Name = undefined,
    Props = undefined,
    Timers = undefined,

    {ok, CleanedKeys} = cleanup_keys(Keys, SName),
    ok = eproc_registry:register_keys(Registry, InstId, Keys),
    ok = eproc_registry:register_name(Registry, InstId, Name),
    {ok, CleanedTimers} = cleanup_timers(Timers, SName),
    {ok, SetupedTimers} = setup_timers(CleanedTimers),
    NewStateData = StateDataAfterInit#state{
        trn_id = TrnId,
        sname = SName,
        sdata = SData,
        keys = CleanedKeys,
        props = Props,
        timers = SetupedTimers
    },
    {noreply, running, NewStateData};

%%
%%  Handles FSM timers.
%%
handle_info({'eproc_fsm$timer', _TimerRef, _Event}, StateName, StateData) ->
    {noreply, StateName, StateData}.


%%
%%  Invoked, when the FSM terminates.
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Create and start FSM.
%%
create_start_link(Module, Args, From, Options, Timeout) ->
    GroupOpts = resolve_group_opts(From, Options),
    {ok, InstId} = create(Module, Args, Options ++ GroupOpts),
    ok = eproc_registry:start_instance(undefined, InstId, [{timeout, Timeout}]),
    {ok, InstId}.


%%
%%  Extracts timeout from the options.
%%
resolve_timeout(Options) ->
    proplists:get_value(timeout, Options, ?DEFAULT_TIMEOUT).


%%
%%  Creates `group` option if needed.
%%
resolve_group_opts(From, Options) ->
    case {proplists:is_defined(group, Options), From} of
        {false, #inst_ref{group = Group}} -> [{group, Group}];
        {false, _} -> [];
        {true, _} -> []
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
%%
%%
handle_actions(_Actions, StateData) ->
    % TODO: Implement.
    {ok, StateData}.


%%
%%
%%
cleanup_keys(Keys, _SName) ->
    % TODO: Implement.
    {ok, Keys}.


%%
%%
%%
cleanup_timers(Timers, _SName) ->
    % TODO: Implement.
    {ok, Timers}.


%%
%%
%%
setup_timers(Timers) ->
    % TODO: Implement.
    {ok, Timers}.




