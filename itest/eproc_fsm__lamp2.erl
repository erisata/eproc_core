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
%%% Example FSM implementation, that uses orthogonal states.
%%%
-module(eproc_fsm__lamp2).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/0, break/1, fix/1, check/1, toggle/1, state/1, recycle/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").

-define(ERROR_NO_LOG_FUN(SD), fun(_Reason) -> {same_state, SD} end).

%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%
%%
%%
create() ->
    StartOpts = [{register, id}],
    CreateOpts = [
        {start_spec, {default, StartOpts}}
    ],
    Args = {},
    Event = create,
    {ok, FsmRef, ok} = eproc_fsm:sync_send_create_event(?MODULE, Args, Event, CreateOpts),
    {ok, FsmRef}.


%%
%%
%%
break(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, break).


%%
%%
%%
fix(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, fix).


%%
%%
%%
check(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, check).


%%
%%
toggle(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, toggle).


%%
%%
%%
% events(FsmRef) ->
%     eproc_fsm:sync_send_event(FsmRef, events).


%%
%%
%%
state(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, state).


%%
%%
%%
recycle(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, recycle).



%%% ============================================================================
%%% Internal data structures.
%%% ============================================================================

-record(operated, {
    condition = '_' :: '_' | waiting | checking | broken | working,
    switch = '_'    :: '_' | on | switching | off
}).

-type state() ::
    initial |
    #operated{} |
    recycled.

-record(data, {
    events, 
    condition
}).



%%% ============================================================================
%%% Callbacks for eproc_fsm.
%%% ============================================================================

%%
%%  FSM init.
%%
init({}) ->
    {ok, initial, #data{}}.


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

%
%   The initial state.
%
state(initial, {sync, _From, create}, StateData) ->
    {reply_next, ok, initializing, StateData};

%
%   The `initializing` state.
%
state(initializing = State, Trigger, StateData) when
    element(1, Trigger) =:= entry;
    Trigger =:= {self, do_initialize};
    Trigger =:= {timer, retry};
    Trigger =:= {timer, giveup}
    ->
    eproc_gen_active:state(State, Trigger, StateData, #{
        do     => {do_initialize, fun configure/1},
        retry  => {retry, 100, step_retry},
        giveup => {giveup, 500, step_giveup, recycled},
        next   => operated,
        error  => ?ERROR_NO_LOG_FUN(StateData)
    });

% ------------------------------------------------------------------------------
%
%   The `operated` state -- this state is orthogonal.
%
state(operated, {entry, _PrevSName}, StateData) ->
    {next_state, #operated{condition = waiting, switch = off}, StateData};

state(#operated{}, {sync, _From, break}, StateData = #data{events = Events, condition = C}) ->
    {reply_next, ok, #operated{condition = broken, switch = off}, StateData#data{events = [off | Events], condition = [broken | C]}};   % NOTE: Both changed.

state(#operated{}, {sync, _From, recycle}, StateData) ->
    {reply_final, ok, recycled, StateData};

state(#operated{}, {exit, _NextState}, StateData) ->
    {ok, StateData};


%
%   The `operated #switch = | on | switching | off,` state.
%
state(#operated{switch = off}, {entry, _PrevSName}, StateData = #data{events = Events}) ->
    {ok, StateData#data{events = [off | Events]}};

state(#operated{switch = Switch}, {sync, _From, toggle}, StateData) ->
    NewSwitch = case Switch of
        on -> off;
        off -> switching
    end,
    {reply_next, ok, #operated{switch = NewSwitch}, StateData};  % NOTE: broken left as '_'


state(#operated{switch = switching} = State, Trigger, StateData) when
        element(1, Trigger) =:= entry;
        Trigger =:= {self, switching};
        Trigger =:= {timer, retry};
        Trigger =:= {timer, giveup}
        ->
    eproc_gen_active:state(State, Trigger, StateData, #{
        do     => {switching, fun switching/1},
        retry  => {retry, 100, step_retry},
        giveup => {giveup, 500, step_giveup, #operated{switch = off }},
        next   => #operated{switch = on},
        error  => ?ERROR_NO_LOG_FUN(StateData)
    });

state(#operated{switch = on}, {entry, _PrevSName}, StateData = #data{events = Events}) ->
    {ok, StateData#data{events = [on | Events]}};


%
%   The `operated #condition =  waiting | checking | working,` state.
%

state(#operated{condition = waiting}, {entry, _PrevSName}, StateData = #data{condition = Cond}) ->
    {ok, StateData#data{condition = [waiting | Cond]}};

state(#operated{condition = waiting}, {sync, _From, check}, StateData) ->
    {reply_next, ok, #operated{condition = checking}, StateData};

state(#operated{condition = working}, {sync, _From, check}, StateData) ->
    {reply_next, ok, #operated{condition = checking}, StateData};

state(#operated{condition = broken}, {sync, _From, check}, StateData) ->
    {reply_next, ok, #operated{condition = checking}, StateData};

state(#operated{condition = checking} = State, Trigger, StateData) when
        element(1, Trigger) =:= entry;
        Trigger =:= {self, checking};
        Trigger =:= {timer, retry};
        Trigger =:= {timer, giveup}
        ->
    eproc_gen_active:state(State, Trigger, StateData, #{
        do     => {checking, fun checking/1},
        retry  => {retry, 100, step_retry},
        giveup => {giveup, 500, step_giveup, #operated{condition = waiting}},
        next   => #operated{condition = working},
        error  => ?ERROR_NO_LOG_FUN(StateData)
    });

state(#operated{condition = working}, {entry, _PrevSName}, StateData = #data{condition = C}) ->
    {ok, StateData#data{condition = [working | C]}};

state(#operated{condition = broken}, {entry, _PrevSName}, StateData = #data{condition = C}) ->
    {ok, StateData#data{condition = [broken | C]}};

state(#operated{condition = broken}, {sync, _From, fix}, StateData = #data{condition = C}) ->
    {reply_next, ok, #operated{condition = working}, StateData#data{condition = [working | C]}};

state(#operated{condition = waiting}, {sync, _From, fix}, StateData = #data{condition = C}) ->
    {reply_next, ok, #operated{condition = working}, StateData#data{condition = [working | C]}};

state(#operated{condition = working}, {sync, _From, fix}, StateData) ->
    {reply_same, ok, StateData};


state(#operated{condition = Broken, switch = Switch}, {sync, _From, state}, StateData) ->
    {reply_same, {ok, {Broken, Switch}}, StateData};


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

switching(StateData = #data{condition = Cond}) ->
    case hd(Cond) of
        working -> 
            lager:info("LAMP IS SWITCHING-ON, Condition= ~p", [Cond]),
            {ok, StateData};
        _ -> 
            lager:error("LAMP IS BROKEN, Condition= ~p", [Cond]),
            {error, Cond}
    end.

checking(StateData = #data{events = Events}) ->
    case hd(Events) of
        on -> 
            lager:info("LAMP IS WORKING, Events= ~p", [Events]),
            {ok, StateData};
        _ -> 
            lager:error("LAMP IS OFF, Events= ~p", [Events]),
            {error, Events}
    end.

configure(StateData = #data{condition = Cond, events = Events}) ->
    NewStateData = StateData#data{
        condition = [],
        events    = []
    },
    lager:info("CONFIGURE NewStateData ~p", [NewStateData]),
    {ok, NewStateData}.

