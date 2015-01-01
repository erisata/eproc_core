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

%%
%%  Scheduler process, that send a message periodically.
%%  This process uses FSM timers and is used to test them.
%%
%%      [] --- start ---> [paused] --- set ---> [scheduling]
%%

-module(eproc_fsm__sched).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start/0, subscribe/1, set/2, cancel/1, pause/1, stop/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

start() ->
    StartOpts = [{register, id}, {start_sync, true}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, FsmRef} = eproc_fsm:send_create_event(?MODULE, {}, start, CreateOpts),
    {ok, FsmRef}.

subscribe(FsmRef) ->
    eproc_fsm:send_event(FsmRef, {add, self()}).

set(FsmRef, Period) ->
    eproc_fsm:send_event(FsmRef, {set, Period}).

cancel(FsmRef) ->
    eproc_fsm:send_event(FsmRef, cancel).

pause(FsmRef) ->
    eproc_fsm:send_event(FsmRef, pause).

stop(FsmRef) ->
    eproc_fsm:send_event(FsmRef, stop).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    subsc,   %% Runtime data
    period
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #state{period = undefined, subsc = undefined}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    {ok, #state.subsc, []}.


%%
%%  The initial state.
%%
handle_state([], {event, start}, StateData) ->
    {next_state, [paused], StateData};


%%
%%  The `paused` state.
%%
handle_state([paused], {event, {set, Period}}, StateData) ->
    {next_state, [scheduling], StateData#state{period = Period}};


%%
%%  The `scheduling` state.
%%
handle_state([scheduling], {entry, _PrevState}, StateData = #state{period = Period}) ->
    ok = eproc_timer:set(main, Period, tick, [scheduling]), % Timer created.
    {ok, StateData};

handle_state([scheduling], {timer, tick}, StateData = #state{subsc = Subscribers}) ->
    lists:foreach(fun (S) -> S ! tick end, Subscribers),
    {next_state, [scheduling], StateData};

handle_state([scheduling], {event, {set, Period}}, StateData) ->
    ok = eproc_timer:set(main, Period, tick, [scheduling]), % Timer updated.
    {same_state, StateData#state{period = Period}};

handle_state([scheduling], {event, cancel}, StateData) ->
    ok = eproc_timer:cancel(main),  % Timer canceled.
    {same_state, StateData};

handle_state([scheduling], {event, pause}, StateData) ->
    {next_state, [paused], StateData};



%%
%%  Any-state handlers
%%
handle_state(_StateName, {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state(_StateName, {event, {add, Subscriber}}, StateData = #state{subsc = Subscribers}) ->
    {same_state, StateData#state{subsc = [Subscriber | Subscribers]}};

handle_state(_StateName, {event, stop}, StateData) ->
    {final_state, [done], StateData};

handle_state(_StateName, {exit, _NextState}, StateData) ->
    {ok, StateData}.



%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



%% =============================================================================
%%  Internal functions.
%% =============================================================================
