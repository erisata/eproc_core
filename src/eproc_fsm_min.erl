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
%%  Simplified version of the `eproc_fsm`
%%  =====================================
%%
%%  This module is a simplified version (for the user) of the `eproc_fsm`.
%%  It requires a minimal set of callback functions. On the other side,
%%  the module is designed is such way, that it can be safelly replaced
%%  by the `eproc_fsm` when requirements for the begaviour increases (state
%%  upgrades should be handled, etc.). Only additional callbach functions
%%  should be provided when migrating a module to the `eproc_fsm` from the
%%  minimal version apart from changed behaviour and the create function.
%%
%%  How `eproc_fsm_min` callbacks are invoked in different scenarios
%%  ----------------------------------------------------------------
%%
%%  New FSM created
%%  :
%%        * `init(Args, InstRef)`
%%        * `handle_state(InitStateName, {event, Message} | {sync, From, Message}, StateData, InstRef)`
%%        * `handle_state(NewStateName, {entry, InitStateName}, StateData, InstRef)`
%%
%%  Event initiated a transition (`next_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData, InstRef)`
%%        * `handle_state(NextStateName, {entry, StateName}, StateData, InstRef)`
%%
%%  Event with no transition (`same_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData, InstRef)`
%%
%%  Event initiated a termination (`final_state`)
%%  :
%%        * `handle_state(StateName, {event, Message} | {sync, From, Message}, StateData, InstRef)`
%%
%%
-module(eproc_fsm_min).
%-behaviour(eproc_fsm).
%-export([init/2, init/3, handle_state/5, code_change/4, terminate/3]).

%init() ->
%    {ok, State}.

% TODO: Hide unknown messages.
