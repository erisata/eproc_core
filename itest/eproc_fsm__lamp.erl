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
-module(eproc_fsm__lamp).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/0, break/1, fix/1, toggle/1, events/1, state/1, recycle/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").


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
toggle(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, toggle).


%%
%%
%%
events(FsmRef) ->
    eproc_fsm:sync_send_event(FsmRef, events).


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
    broken = '_'    :: '_' | yes | no,
    switch = '_'    :: '_' | on | off
}).

-type state() ::
    initial |
    #operated{} |
    recycled.

-record(data, {
    events = []
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
%%  Handle all transitions.
%%

%
%   The initial state.
%
-spec handle_state(state(), term(), #data{}) -> term().

handle_state(initial, {sync, _From, create}, StateData) ->
    {reply_next, ok, #operated{_ = initial}, StateData};


%
%   The `operated` state -- this state is orthogonal.
%
handle_state(#operated{switch = initial}, {entry, _PrevSName}, StateData) ->
    {next_state, #operated{switch = off}, StateData};  % broken = no,

handle_state(#operated{switch = on}, {entry, _PrevSName}, StateData = #data{events = Events}) ->
    {ok, StateData#data{events = [on | Events]}};

handle_state(#operated{switch = off}, {entry, _PrevSName}, StateData = #data{events = Events}) ->
    {ok, StateData#data{events = [off | Events]}};

handle_state(#operated{broken = initial}, {entry, _PrevSName}, StateData) ->
    {next_state, #operated{broken = no}, StateData};

handle_state(#operated{}, {entry, _PrevSName}, StateData) ->
    % NOTE: We don't handle lamp brokes and fixes.
    {ok, StateData};

handle_state(#operated{}, {sync, _From, break}, StateData) ->
    {reply_next, ok, #operated{broken = yes}, StateData}; % NOTE: switch left as '_'.

handle_state(#operated{broken = yes}, {sync, _From, fix}, StateData) ->
    {reply_next, ok, #operated{broken = no, switch = off}, StateData}; % NOTE: Both changed.

handle_state(#operated{broken = no}, {sync, _From, fix}, StateData) ->
    {reply_same, ok, StateData};

handle_state(#operated{switch = Switch}, {sync, _From, toggle}, StateData) ->
    NewSwitch = case Switch of
        on -> off;
        off -> on
    end,
    {reply_next, ok, #operated{switch = NewSwitch}, StateData};  % NOTE: broken left as '_'

handle_state(#operated{}, {sync, _From, events}, StateData = #data{events = Events}) ->
    {reply_same, {ok, lists:reverse(Events)}, StateData#data{events = []}};

handle_state(#operated{broken = Broken, switch = Switch}, {sync, _From, state}, StateData) ->
    {reply_same, {ok, {Broken, Switch}}, StateData};

handle_state(#operated{}, {sync, _From, recycle}, StateData) ->
    {reply_final, ok, recycled, StateData};

handle_state(#operated{}, {exit, _NextState}, StateData) ->
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



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


