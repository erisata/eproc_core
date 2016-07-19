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
%%  Void process for testing `eproc_fsm`. Terminates immediatelly after
%%  creation. The states are the following:
%%
%%      initial --- done ---> done.
%%
-module(eproc_fsm__void).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/0, create/1, start_link/1, done/1, close/1, self_done/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include("eproc.hrl").

-define(REF(FsmRef), {via, gproc, {n, l, FsmRef}}).

%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
create() ->
    eproc_fsm:create(?MODULE, {}, initial).


%%
%%
%%
create(Name) ->
    eproc_fsm:create(?MODULE, {}, [{name, Name}]).


%%
%%
%%
start_link(FsmRef) ->
    eproc_fsm:start_link(?REF(FsmRef), FsmRef, initial).


%%
%%
%%
done(FsmRef) ->
    eproc_fsm:send_event(?REF(FsmRef), done).


%%
%%  Closes the FSM in several steps withing single transition.
%%
close(Pid) when is_pid(Pid) ->
    eproc_fsm:send_event(Pid, close);

close(FsmRef) ->
    eproc_fsm:send_event(?REF(FsmRef), close).


%%
%%  Closes the FSM by sending itself the done event.
%%
self_done(Pid) when is_pid(Pid) ->
    eproc_fsm:send_event(Pid, self_done).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {some}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, initial, #state{}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%
%%
handle_state(initial, {event, done}, StateData) ->
    {final_state, done, StateData};


handle_state(initial, {event, close}, StateData) ->
    {next_state, closing, StateData};

handle_state(closing, {entry, initial}, StateData) ->
    {final_state, closed, StateData};


handle_state(initial, {event, self_done}, StateData) ->
    ok = eproc_fsm:self_send_event(done),
    {next_state, waiting, StateData};

handle_state(waiting, {entry, initial}, StateData) ->
    {ok, StateData};

handle_state(waiting, {self, done}, StateData) ->
    {final_state, done, StateData};

handle_state(waiting, {exit, done}, StateData) ->
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

