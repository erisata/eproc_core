%/--------------------------------------------------------------------
%| Copyright 2013-2018 Erisata, UAB (Ltd.)
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
%%  Testcases for `eproc_gen_active'.
%%
-module(eproc_gen_active_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    test_orthogonal_states/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_orthogonal_states
    ].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:load(eproc_core),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    application:set_env(eproc_core, store, {eproc_store_ets, ref, []}),
    application:set_env(eproc_core, registry, {eproc_reg_gproc, ref, []}),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = application:ensure_all_started(eproc_core),
    {ok, Store} = eproc_store:ref(),
    {ok, Registry} = eproc_registry:ref(),
    [{store, Store}, {registry, Registry} | Config].


%%
%%  CT API, cleanup.
%%
end_per_suite(_Config) ->
    ok = application:stop(gproc),
    ok = application:stop(eproc_core).


%%
%%  Log test case name at start
%%
init_per_testcase(TestCase, Config) ->
    lager:debug("-------------------------------------- ~p start", [TestCase]),
    Config.


%%
%%  Log test case name at end
%%
end_per_testcase(TestCase, _Config) ->
    lager:debug("-------------------------------------- ~p end", [TestCase]),
    ok.


%%% ============================================================================
%%% Mocks and helper functions.
%%% ============================================================================

% Mocks
state(FsmRef, Timeout) ->
    ok = timer:sleep(Timeout),
    case eproc_test:get_state(FsmRef, [running_only]) of
        {ok, running, SName, _SData} ->
            {ok, SName};
        {ok, Status, _SName, _SData} ->
            {error, Status};
        {error, Error} ->
            {error, Error}
    end.

mock_opening(StateData) ->
    ok = timer:sleep(50),
    Results = {ok, StateData},
    ok = meck:expect(eproc_fsm_reading, opening, Results).



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Test orthogonal active states.
%%
%%   1) Lamp process sucessfully pass gen_active initializing state and creates
%%      2 initial orthogonal states: {operated, condition = waiting, switch = off}
%%   2) first time Lamp 'switching' state doesn't meet condition 'working' retrying and giving up, 
%%   3) after 'fix' event change Lamp condition to 'working', 'switching' pass to 'on',
%%   4) 'check' event succesfully pass genactive 'checking' state,
%%   5) 'break' event changes condition to 'broken' and Lamp goes to 'recycled' state.
%%
test_orthogonal_states(_Config) ->
    % Mocks
    ok = meck:new(eproc_timer, [passthrough]),
    % Test
    {ok, Lamp}                     = eproc_fsm__lamp_gen_active:create(),           % It is turned off, when created.
    {ok, {operated, waiting, off}} = state(Lamp, 50),
    ok                                   = eproc_fsm__lamp_gen_active:toggle(Lamp), % Switching on.
    {ok, {operated, waiting, switching}} = state(Lamp, 50),
    ok                   = timer:sleep(500),                            % Wait for switching giveup.
    {ok, {waiting, off}} = eproc_fsm__lamp_gen_active:state(Lamp),
    ok                   = eproc_fsm__lamp_gen_active:fix(Lamp),        % Switch state does not change here.
    {ok, {working, off}} = eproc_fsm__lamp_gen_active:state(Lamp),
    ok                   = eproc_fsm__lamp_gen_active:toggle(Lamp),     % Switching on 2.
    {ok, {working, on}}  = eproc_fsm__lamp_gen_active:state(Lamp),
    ok                   = eproc_fsm__lamp_gen_active:check(Lamp),      % Checking at the same time
    {ok, {working, on}}  = eproc_fsm__lamp_gen_active:state(Lamp),
    % Test results
    6 = meck:num_calls(eproc_timer, set, [step_retry, '_', retry, {operated,'_',switching}]),
    2 = meck:num_calls(eproc_timer, set, [step_giveup, '_', '_', {operated,'_',switching}]),
    1 = meck:num_calls(eproc_timer, set, [step_retry, '_', retry, {operated, checking, '_'}]),
    1 = meck:num_calls(eproc_timer, set, [step_giveup, '_', '_', {operated, checking, '_'}]),
    ok = meck:unload([eproc_timer]),
    ok.


