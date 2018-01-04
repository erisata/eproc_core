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
%%% Example FSM implementation, that uses active states.

%%%     [] --- start ---> paused --- set ---> scheduling
%%%
-module(eproc_fsm_reading).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([start/0, read/1, stop/1]).
-export([init/1, init/2, handle_state/3, state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").

-define(ERROR_NO_LOG_FUN(SD), fun(_Reason) -> {same_state, SD} end).

%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%
%%
start() ->
    StartOpts = [{register, id}],
    CreateOpts = [
        {start_spec, {default, StartOpts}}
    ],
    Args = {},
    Event = start,
    {ok, FsmRef, ok} = eproc_fsm:sync_send_create_event(?MODULE, Args, Event, CreateOpts),
    {ok, FsmRef}.

%%
%%
read(FsmRef) ->
    eproc_fsm:send_event(FsmRef, read).


stop(FsmRef) ->
    eproc_fsm:send_event(FsmRef, stop).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-type state() ::
    initial |
    opening |
    waiting |
    doing |
    wait |
    timeouted |
    stopped |
    done.

-record(data, {
    events = [],
    close_time = {2, s},
    reading
}).



%%% ============================================================================
%%% Callbacks for eproc_fsm.
%%% ============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, initial, #data{events = []}}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  Handle all state events and transitions.
%%
handle_state(StateName, Trigger, StateData) ->
    case Trigger of
        {sync, _From, Event} ->
            lager:debug("@~p: ~p", [StateName, {sync, Event}]);
        _ ->
            lager:debug("@~p: ~p", [StateName, Trigger])
    end,
    case Trigger of
        {exit, _} -> {ok, StateData};
        _         -> state(StateName, Trigger, StateData)
    end.


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

%%% ============================================================================
%%% State events and transitions.
%%% ============================================================================


%%
%%  All state transitions, grouped by originating state.
%%
-spec state(state(), term(), #data{}) -> term().

% ------------------------------------------------------------------------------
%   All state events.
%
state(AnyState, {event, stop}, StateData) ->
    lager:warning("Force stopping process @~p.", [AnyState]),
    {final_state, stopped, StateData};

%%
%%  The `initial` state.
%%
state(initial, {sync, _From, start}, StateData = #data{events = Events}) ->
    {reply_next, ok, opening, StateData#data{events = [start | Events]}};

%%
%%  The `opening` state.
%%
state(opening = State, Trigger, StateData) when
        element(1, Trigger) =:= entry;
        Trigger =:= {self, do_open};
        Trigger =:= {timer, retry};
        Trigger =:= {timer, giveup}
        ->
    eproc_gen_active:state(State, Trigger, StateData, #{
        do     => {do_open, fun opening/1},
        retry  => {retry, 100, step_retry},
        giveup => {giveup, 500, step_giveup, waiting},
        next   => waiting,
        error  => ?ERROR_NO_LOG_FUN(StateData)
    });

% ------------------------------------------------------------------------------
%%
%%  The `waiting` state.
%%
state(waiting, {entry, _PrevState}, StateData) ->
    {next_state, doing, StateData};

state({waiting, SubState}, {sync, _From, {event, read}}, StateData = #data{events = Events}) ->
    {next_state, doing, StateData#data{events = [read | Events], reading = read}};

%%
%%  The `doing` state.
%%
state(doing = State, Trigger, StateData) when
        element(1, Trigger) =:= entry;
        Trigger =:= {self, do_smthng};
        Trigger =:= {timer, retry};
        Trigger =:= {timer, giveup}
        ->
    eproc_gen_active:state(State, Trigger, StateData, #{
        do     => {do_smthng, fun do_smthng/1},
        retry  => {retry, 100, step_retry},
        giveup => {giveup, 500, step_giveup, wait},
        next   => wait,
        error  => ?ERROR_NO_LOG_FUN(StateData)
    });

state(doing, {event, read}, StateData = #data{events = Events}) ->
    {next_state, wait, StateData#data{events = [read | Events], reading = read}};

%%
%%  The `wait` state.
%%
state(wait, {entry, _PrevState}, StateData) ->
    {same_state, StateData};

state(wait, {event, read}, StateData = #data{events = Events}) ->
    {next_state, doing, StateData#data{events = [read | Events], reading = read}};

%
%   Unknown events.
%
state(AnyState, {self, Unknown}, StateData) ->
    lager:warning("Dropping unknown self event ~p @~p", [Unknown, AnyState]),
    {same_state, StateData};

state(AnyState, {timer, Unknown}, StateData) ->
    lager:warning("Dropping unknown timer ~p @~p", [Unknown, AnyState]),
    {same_state, StateData};

state(AnyState, {event, Unknown}, StateData) ->
    lager:warning("Dropping unknown async event ~p @~p", [Unknown, AnyState]),
    {same_state, StateData};

state(AnyState, {sync, _From, Unknown}, StateData) ->
    lager:warning("Dropping unknown sync event ~p @~p", [Unknown, AnyState]),
    {reply_same, {error, {cannot_be_processed_in_current_state, AnyState}}, StateData};

state(AnyState, {info, Unknown}, StateData) ->
    lager:warning("Dropping unknown message ~p @~p", [Unknown, AnyState]),
    {same_state, StateData}.


%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


opening(StateData = #data{events = Events}) ->
    case Events of
        [_] -> 
            lager:info("DO OPENING ~p", [Events]),
            {ok, StateData};
        [] -> 
            lager:error("Failed to open process ~p", [Events]),
            {error, Events}
    end.

do_smthng(StateData = #data{reading = Reading}) ->
    case Reading of
        read -> 
            lager:info("DO SOMETHING ~p", [Reading]),
            {ok, StateData};
        _ -> 
            lager:error("SOMETHING Failed to open process, reading= ~p", [Reading]),
            {error, Reading}
    end.
