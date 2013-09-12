%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%      initial --- Event ---> [ready] --- on_entry ---> final([done]).
%%

-module(eproc_fsm_void).
-behaviour(eproc_fsm).
-export([init/3, handle_state/5, handle_status/4, state_change/2]).

-record(state, {}).


%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%
%%
init(_Definition, _Event, _InstRef) ->
    {ok, [ready], #state{}}.


%%
%%
%%
handle_state([ready], entry, initial, StateData, _InstRef) ->
    {final_state, [done], StateData}.


%%
%%
%%
handle_status(_StateName, _StateData, Query, MediaType) ->
    {error, undefined}.


%%
%%
%%
state_change(StateData = #state{}, _InstRef) ->
    {ok, StateData}.


