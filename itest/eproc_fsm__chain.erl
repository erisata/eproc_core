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

%%%
%%% Process that calls other processes of the same type.
%%% It is used to test inter-FSM calls.
%%%
-module(eproc_fsm__chain).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([new/0, new/1, add/3, sum/2, stop/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%
%%
new() ->
    new(undefined).

new(NextFsmRef) ->
    StartOpts = [{register, id}],
    CreateOpts = [{start_spec, {default, StartOpts}}],
    {ok, FsmRef} = eproc_fsm:send_create_event(?MODULE, {NextFsmRef}, start, CreateOpts),
    {ok, FsmRef}.

%%
%%
%%
add(FsmRef, AddNumber, Depth) ->
    eproc_fsm:send_event(FsmRef, {add, AddNumber, Depth}).


%%
%%
%%
sum(FsmRef, Depth) ->
    eproc_fsm:sync_send_event(FsmRef, {sum, Depth}).


%%
%%
%%
stop(FsmRef) ->
    eproc_fsm:send_event(FsmRef, stop).


%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    num     :: integer(),
    next    :: fsm_ref() | undefined
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({Next}) ->
    {ok, active, #state{num = 0, next = Next}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state(active, {event, start}, StateData) ->
    {same_state, StateData};

handle_state(active, {event, {add, AddNumber, Depth}}, StateData = #state{num = Number, next = Next}) ->
    NewNumber = Number + AddNumber,
    case Depth of
        0 -> ok;
        _ -> ?MODULE:add(Next, AddNumber, Depth - 1)
    end,
    {same_state, StateData#state{num = NewNumber}};

handle_state(active, {sync, _From, {sum, Depth}}, StateData = #state{num = Number, next = Next}) ->
    TailSum = case Depth of
        0 -> 0;
        _ -> ?MODULE:sum(Next, Depth - 1)
    end,
    {reply_same, Number + TailSum, StateData};

handle_state(active, {event, stop}, StateData) ->
    {final_state, done, StateData};

handle_state(active, {exit, done}, StateData) ->
    {ok, StateData}.


%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(_OldVsn, StateName, StateData = #state{}, _Extra) ->
    {ok, StateName, StateData}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


