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
%%  Testcases for `eproc_fsm`.
%%
-module(eproc_gen_active_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    test_active_states/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_active_states
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
%%  Test active states.
%%
test_active_states(_Config) ->
    % Mocks
    % StateData = { [], {2, s} },
    % ok = mock_opening(StateData),

    % test
    {ok, Read} = eproc_fsm_reading:create(),
    ok = meck:wait(eproc_fsm_reading, opening, [{ok, Read}], 10),
    {ok, doing} = state(Read, 50),

    ok = timer:sleep(550),                      % Wait for giveup.
    % {ok, wait} = state(eproc_fsm_reading, Read, 50),
    % ok = eproc_gen_active:state('_', doing, {timer,giveup}, '_'),
    ok = eproc_fsm_reading:read(Read),
    
    % {ok, '_'} = eproc_test:get_state(Read, [running_only]),
    {ok, wait} = state(Read, 50),
    % ok = timer:sleep(50),  % Wait for doing read.
    ok = eproc_fsm_reading:stop(Read),
    ok.


%%
%%  TODO: Send msg.
%%


%%
%%  Clear msg inbox.
%%
flush_msgs() ->
    receive _ -> flush_msgs()
    after 0 -> ok
    end.

