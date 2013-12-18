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
%%    * Callback `Module:handle_state/3` is used instead of `Module:StateName/2-3`.
%%      This allows to have substates and orthogonal states.
%%    * Process configuration is passed as a separate argument to the fsm. TODO: WTF?
%%    * Has support for state entry and exit actions.
%%      State entry action is convenient for setting up timers and keys.
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
%%        * `init(Args)`
%%        * `init(InitStateName, StateData)`
%%        * `handle_state(InitStateName, {event, Message} | {sync, From, Message}, StateData)`
%%        * `handle_state(NewStateName, {entry, InitStateName}, StateData)`
%%
%%  FSM process terminated
%%  :
%%        * `terminate(Reason, StateName, StateData)`
%%
%%  FSM is restarted
%%  :
%%        * `code_change(state, StateName, StateData, undefined)`
%%        * `init(StateName, StateData)`
%%
%%  FSM upgraded in run-time
%%  :
%%        * `code_change(OldVsn, StateName, StateData, Extra)`
%%
%%  FSM is resumed after being suspended
%%  :
%%        * `code_change(state, StateName, StateData, undefined)`
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
-module(eproc_fsm).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).

%%
%%  Client-side functions.
%%
-export([
    create/3, start_link/2, await/2, id/0, group/0,
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
-export_type([name/0, id/0, group/0]).

%%
%%  Internal things...
%%
-include("eproc.hrl").
-define(DEFAULT_TIMEOUT, 10000).


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
-opaque group() :: integer().
-type prop_elem() :: list() | binary() | integer().
-type event_src() :: undefined | term(). %% TODO: Add an alternative to #inst_ref{} |

-type timer_name() :: term().

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
-type state_effect() ::
    {name, Name :: term()} |
    {key, Key :: term(), Scope :: state_scope()} |  % Options are left as undocumented feature.
    {prop, PropName :: prop_elem(), PropValue :: prop_elem()} |
    {timer, TimerName :: term(), After :: integer(), Event :: state_event(), Scope :: state_scope()} |
    {timer, TimerName :: term(), cancel}.


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
%%  The function needs to return `StateData` - internal state of the process
%%  and optionally effects and initial state name. If `InitStateName` is not
%%  provided, the the initial state name `[]` is assumed. Effects can be used
%%  here to set FSM name, keys, properties and timers.````
%%
-callback init(
        Args :: term()
    ) ->
        {ok, StateData} |
        {ok, StateData, Effects} |
        {ok, InitStateName, StateData, Effects}
    when
        StateData :: state_data(),
        InitStateName :: state_name(),
        Effects :: [state_effect()].

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
%%  :   is the corresponding state data.
%%
%%  The function should return state data and state name. They both can be transformed
%%  in this function. Nevertheless, the transformed state will only be persisted on the
%%  next transition.
%%
-callback init(
        StateName :: state_name(),
        StateData :: state_data()
    ) ->
        {ok, NextStateName, NewStateData}
    when
        NextStateName :: state_name(),
        NewStateData  :: state_data().

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
%%  `{same_state, NewStateData, Effects}`
%%  :   to indicate, that transition is to the the same state. In this case, corresponding
%%      state exit and entry callbacks will not be invoked. The term Effects is optional (in all cases).
%%  `{next_state, NextStateName, NewStateData, Effects}`
%%  :   indicates a transition to the next state. Next state can also be the current state,
%%      but in this case state exit/entry callbacks will be invoked anyway.
%%  `{final_state, FinalStateName, NewStateData, Effects}`
%%  :   indicates a transition to the final state of the FSM. I.e. FSM is terminated after
%%      this transition. Not all effects are meaningfull in the case of final state, but
%%      assignment of keys or properties can be useful.
%%
%%  In the case of synchronous events `{sync, From, Message}`, the callback can return all the
%%  responses listed above, if reply to the caller was sent explicitly using function `reply/2`.
%%  If reply was not sent explicitly, the terms tagged with `reply_same`, `reply_next` and `reply_final`
%%  should be used to send a reply and do the transition. Meaning of these response terms are
%%  the same as for the `same_state`, `next_state` and `final_state` correspondingly.
%%
%%  If the callback was invoked to handle state exit or entry, the response term should be
%%  `{ok, NewStateData}` or `{ok, NewStateData, Effects}`.
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
        {same_state, NewStateData, Effects} |
        {next_state, NextStateName, NewStateData} |
        {next_state, NextStateName, NewStateData, Effects} |
        {final_state, FinalStateName, NewStateData} |
        {final_state, FinalStateName, NewStateData, Effects} |
        {reply_same, Reply, NewStateData} |
        {reply_same, Reply, NewStateData, Effects} |
        {reply_next, Reply, NextStateName, NewStateData} |
        {reply_next, Reply, NextStateName, NewStateData, Effects} |
        {reply_final, Reply, FinalStateName, NewStateData} |
        {reply_final, Reply, FinalStateName, NewStateData, Effects} |
        {ok, NewStateData} |
        {ok, NewStateData, Effects}
    when
        From    :: term(),
        Timer   :: timer_name(),
        Reply   :: term(),
        NewStateData    :: state_data(),
        NextStateName   :: state_name(),
        PrevStateName   :: state_name(),
        FinalStateName  :: state_name(),
        Effects         :: [state_effect()].


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
        {ok, NextStateName, NewStateData}
    when
        Vsn     :: term(),
        Extra   :: term(),
        NextStateName :: state_name(),
        NewStateData  :: state_data().

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
        Status :: term
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
    case Module:init(Args) of
        {ok, StateData} ->
            StateName = [],
            Effects = [];
        {ok, StateData, Effects} ->
            StateName = [];
        {ok, StateName, StateData, Effects} ->
            ok
    end,

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
%%  Returns instance id of the FSM, if invoked from its process.
%%
-spec id() -> {ok, id()} | {error, not_fsm}.

id() ->
    case erlang:get('eproc_fsm$id') of
        undefined ->
            {error, not_fsm};
        Id ->
            {ok, Id}
    end.


%%
%%  Returns instance group of the FSM, if invoked from its process.
%%
-spec group() -> {ok, group()} | {error, not_fsm}.

group() ->
    case erlang:get('eproc_fsm$group') of
        undefined ->
            {error, not_fsm};
        Group ->
            {ok, Group}
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
%%  syncer FSM or new group will be created if mesage is from an external source.
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
    % TODO: The following is the second remote sync in the case of riak.
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
    % TODO: The following is the second remote sync in the case of riak.
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
    gen_fsm:reply(To, Reply).


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
%%  Internal state of the module.
%% =============================================================================

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
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({InstId, _Options}) ->
    {ok, Registry} = eproc_registry:ref(),
    {ok, Store}    = eproc_store:ref(),
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
    undefined = erlang:put('eproc_fsm$id', InstId),
    undefined = erlang:put('eproc_fsm$group', Group),
    case Transition of
        undefined ->
            %%
            %%  Initial startup.
            %%
            TrnId = undefined,
            case Module:init(Args, undefined) of              %% TODO: Call different callback.
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
%%  Resolves FSM create options.
%%
%%    * Group is taken from the context of the calling process
%%      if not provided in the options explicitly. If the calling
%%      process is not FSM, new group will be created.
%%
resolve_create_opts(group, Options) ->
    case proplists:is_defined(group, Options) of
        true -> [];
        false ->
            case group() of
                {ok, Group} -> [{group, Group}];
                {error, not_fsm} -> [{group, new}]
            end
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




