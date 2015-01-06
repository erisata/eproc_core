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
%%  Process that serves single value generated on init.
%%  This process uses FSM runtime data functionality and is used to test it.
%%
%%      [] --- get ---> [serving]
%%

-module(eproc_fsm__cache).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, crash/1, get/1, stop/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

new() ->
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, FsmRef, _} = eproc_fsm:sync_send_create_event(?MODULE, {}, get, CreateOpts),
    {ok, FsmRef}.

crash(FsmRef) ->
    eproc_fsm:send_event(FsmRef, crash).

get(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, get).

stop(FsmRef) ->
    eproc_fsm:send_event(FsmRef, stop).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    data    % Runtime data.
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, #state{data = undefined}}.


%%
%%  Runtime init.
%%
init(_StateName, #state{data = undefined}) ->
    {ok, #state.data, erlang:now()}.


%%
%%  The initial state.
%%
handle_state([], {sync, _From, get}, StateData = #state{data = Data}) ->
    {reply_next, {ok, Data}, [serving], StateData};


%%
%%  The `serving` state.
%%
handle_state([serving], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([serving], {sync, _From, get}, StateData = #state{data = Data}) ->
    {reply_same, {ok, Data}, StateData};

handle_state([serving], {event, crash}, #state{data = Data}) ->
    undefined = Data;

handle_state([serving], {event, stop}, StateData) ->
    {final_state, [done], StateData};

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
