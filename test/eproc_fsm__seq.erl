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
%%      [] --- reset ---> [serving].
%%

-module(eproc_fsm__seq).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/0, start_link/1, next/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
create() ->
    eproc_fsm:create(?MODULE, {}, []).


%%
%%
%%
start_link(InstId) ->
    eproc_fsm:start_link(InstId, []).


%%
%%  Business specific functions.
%%

reset(InstId) ->
    eproc_fsm:send_event(InstId, reset).

skip(InstId) ->
    eproc_fsm:send_event(InstId, skip).

next(InstId) ->
    eproc_fsm:sync_send_event(InstId, next).

last(InstId) ->
    eproc_fsm:sync_send_event(InstId, last).

close(InstId) ->
    eproc_fsm:send_event(InstId, close).





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
    {next_state, [serving], StateData#state{seq = 0}};


%%
%%  The `serving` state.
%%
handle_state([serving], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([serving], {event, reset}, StateData) ->
    {next_state, [serving], StateData#state{seq = 0}};

handle_state([serving], {event, skip}, StateData = #state{seq = Seq}) ->
    {same_state, StateData#state{seq = Seq + 1}};

handle_state([serving], {sync, _From, next}, StateData = #state{seq = Seq}) ->
    {reply_same, {ok, Seq}, StateData#state{seq = Seq + 1}};

handle_state([serving], {sync, _From, last}, StateData = #state{seq = Seq}) ->
    {reply_final, {ok, Seq}, [closed], StateData};

handle_state([serving], {event, close}, StateData) ->
    {final_state, [closed], StateData};

handle_state([serving], {exit, _NextState}, StateData) ->
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

