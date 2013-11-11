%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%  Main behaviour to be implemented by a user of the `eproc`.
%%
%%  This module designed by taking into account UML FSM definition
%%  as well as the Erlang/OTP `gen_fsm`. The following is the list
%%  of differences comparing it to `gen_fsm`:
%%
%%    * State name supports substates and orthogonal states.
%%    * Callback `Module:handle_state/4` is used instead of `Module:StateName/2-3`.
%%    * Process configuration is passed as a separate argument to the fsm.
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
%%  FSM can reach the following terminal states:
%%    * `{done, success}` - when the FSM was completed successfully.
%%    * `{done, failure}` - when the FSM was completed by the callback module returning special response TODO.
%%    * `{term, killed}`  - when the FSM was killed in the `running` or the `paused` state.
%%    * `{term, failed}`  - when the FSM was terminated in the `faulty` state.
%%
-module(eproc_fsm).
-behaviour(gen_fsm).
-compile([{parse_transform, lager_transform}]).
-export([
    create/0,
    start_link/6,
    send_create_event/0,
    sync_send_create_event/0,
    sync_send_create_event/1,
    send_event/2,
    sync_send_event/2,
    sync_send_event/3,
    kill/2,
    suspend/2,
    resume/2,
    set_state/4
]).
-export([reply/2]).
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
-export([initializing/2, initializing/3, running/2, running/3, paused/2, paused/3, faulty/2, faulty/3]).
-export_type([name/0, inst_id/0, inst_ref/0]).
-include("eproc.hrl").


%%
%%  Structure, passed to all callbacks, to be used to indicate process.
%%
-record(inst_ref, {
}).

-type name() :: {via, Registry :: module(), InstanceId :: inst_id()}.
-opaque inst_id()   :: integer().
-opaque inst_ref()  :: #inst_ref{}.
-type state_event() :: term().
-type state_name()  :: list().
-type state_data()  :: term().
-type state_action() :: term().
-type state_phase() :: event | entry | exit.


%%
%%  Internal state of the `eproc_fsm`.
%%
-record(state, {
    inst_id,
    module,
    registry,
    store,
    options
}).



%% =============================================================================
%%  Callback definitions.
%% =============================================================================


%%
%%  Invoked when initializing the FSM. This fuction is invoked only on first
%%  initialization. I.e. it is not invoked on restarts.
%%
-callback init(
        #definition{},
        state_event(),
        inst_ref()
    ) ->
    {ok, state_name(), state_data()} |
    {ok, state_name(), state_data(), [state_action()]}.


%%
%%
%%
-callback handle_state(
        state_name(),
        state_phase(),
        state_event() | state_name(),
        state_data(),
        inst_ref()
    ) ->
    {same_state, state_data()} |
    {same_state, state_data(), [state_action()]} |
    {next_state, state_name(), state_data()} |
    {next_state, state_name(), state_data(), [state_action()]} |
    {final_state, state_name(), state_data()}.


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
%%
%%
-callback state_change(
        OldStateData    :: state_data(),
        InstRef         :: inst_ref()
    ) ->
    {ok, NewStateData :: state_data()}.



%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%
%%
create() ->
    ok.


%%
%%  Start new eproc_fsm instance.
%%
%%  `Name` is used to identify the FSM instance. Name should always be provided
%%      in the form of `{via, module(), term()}`. This notation is compatible with
%%      the standard OTP process registry behaviour. The registry provided in this
%%      parameter is also used to reference other processes (can be overriden using options).
%%  `Module` is a callback module implementing `eproc_fsm` behaviour.
%%  `Args` is passed to the `Module:init/3` function as the `Args` parameter. This
%%      is similar to the Args parameter in `gen_fsm` and other OTP behaviours.
%%  `Event` stands for the initial event of the FSM, i.e. event that created the FSM.
%%      This event is used for invoking state transition callbacks for the transition
%%      from the `initial` state.
%%  `Store' is used to persist FSM state. One can use either void, transient or
%%      persistent store implementations.
%%
-spec start_link(
        Name    :: name(),
        Module  :: module(),
        Args    :: term(),
        Event   :: state_event(),
        Store   :: store_ref(),
        Options :: proplist()
        ) ->
        {ok, pid()} | ignore | {error, term()}.

start_link(Name = {via, Registry, InstanceId}, Module, Args, Event, Store, Options) ->
    gen_fsm:start_link(Name, ?MODULE, {InstanceId, Module, Args, Event, Registry, Store, Options}).


%%
%%
%%
send_create_event() ->
    %create(),
    %start_link(),
    %send_event(),
    ok.


%%
%%
%%
sync_send_create_event() ->
    ok.


%%
%%
%%
sync_send_create_event(_Timeout) ->
    ok.


%%
%%
%%
send_event(Name, Event) ->
    gen_fsm:send_event(Name, {'eproc_fsm$send_event', Event}).


%%
%%
%%
sync_send_event(Name, Event) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$sync_send_event', Event}).


%%
%%
%%
sync_send_event(Name, Event, Timeout) ->
    gen_fsm:sync_send_event(Name, {'eproc_fsm$sync_send_event', Event}, Timeout).


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


%% =============================================================================
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%  The initialization is implemented asynchronously to avoid timeouts when
%%  restarting the engine with a lot of running fsm's.
%%
init({InstanceId, Module, Args, Event, Registry, Store, Options}) ->
    State = #state{
        inst_id     = InstanceId,
        module      = Module,
        registry    = Registry,
        store       = Store,
        options     = Options
    },
    self() ! {'eproc_fsm$init', Args, Event},
    {ok, initializing, State}.


%%
%%  Handles the `initializing` state.
%%
initializing(_Event, State) ->
    {noreply, State}.

initializing(_Event, _From, State) ->
    {reply, ok, State}.


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
%%  Does asynchronous initialization.
%%
handle_info({'eproc_fsm$init', _Args, _Event}, initializing, StateData) ->
    {noreply, running, StateData};

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

