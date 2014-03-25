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
%%  Sequence-generating process for testing `eproc_fsm`. Terminates never.
%%  The states are the following:
%%
%%      [] --- reset ---> [incrementing] --- flip ---> [decrementing].
%%

-module(eproc_fsm__seq).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, reset/1, skip/1, close/1, next/1, get/1, last/1, flip/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

new() ->
    lager:debug("Creating new SEQ."),
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    eproc_fsm:send_create_event(?MODULE, {}, reset, CreateOpts).

reset(FsmRef) ->
    eproc_fsm:send_event(FsmRef, reset).

skip(FsmRef) ->
    eproc_fsm:send_event(FsmRef, skip).

close(FsmRef) ->
    eproc_fsm:send_event(FsmRef, close).

next(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, next).

get(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, get).

last(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, last).

flip(FsmRef) ->
    eproc_fsm:send_event(FsmRef, flip).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    seq :: integer()
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #state{seq = undefined}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state([], {event, reset}, StateData) ->
    {next_state, [incrementing], StateData#state{seq = 0}};


%%
%%  The `incrementing` state.
%%
handle_state([incrementing], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([incrementing], {event, reset}, StateData) ->
    {next_state, [incrementing], StateData#state{seq = 0}};

handle_state([incrementing], {event, flip}, StateData) ->
    {next_state, [decrementing], StateData};

handle_state([incrementing], {event, skip}, StateData = #state{seq = Seq}) ->
    {same_state, StateData#state{seq = Seq + 1}};

handle_state([incrementing], {event, close}, StateData) ->
    {final_state, [closed], StateData};

handle_state([incrementing], {sync, _From, next}, StateData = #state{seq = Seq}) ->
    {reply_next, {ok, Seq + 1}, [incrementing], StateData#state{seq = Seq + 1}};

handle_state([incrementing], {sync, _From, get}, StateData = #state{seq = Seq}) ->
    {reply_same, {ok, Seq}, StateData};

handle_state([incrementing], {sync, _From, last}, StateData = #state{seq = Seq}) ->
    {reply_final, {ok, Seq}, [closed], StateData};

handle_state([incrementing], {exit, _NextState}, StateData) ->
    {ok, StateData};


%%
%%  The `decrementing` state.
%%
handle_state([decrementing], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([decrementing], {event, reset}, StateData) ->
    {next_state, [decrementing], StateData#state{seq = 0}};

handle_state([decrementing], {event, flip}, StateData) ->
    {next_state, [incrementing], StateData};

handle_state([decrementing], {event, skip}, StateData = #state{seq = Seq}) ->
    {same_state, StateData#state{seq = Seq - 1}};

handle_state([decrementing], {event, close}, StateData) ->
    {final_state, [closed], StateData};

handle_state([decrementing], {sync, _From, next}, StateData = #state{seq = Seq}) ->
    {reply_next, {ok, Seq - 1}, [decrementing], StateData#state{seq = Seq - 1}};

handle_state([decrementing], {sync, _From, get}, StateData = #state{seq = Seq}) ->
    {reply_same, {ok, Seq}, StateData};

handle_state([decrementing], {sync, _From, last}, StateData = #state{seq = Seq}) ->
    {reply_final, {ok, Seq}, [closed], StateData};

handle_state([decrementing], {exit, _NextState}, StateData) ->
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
