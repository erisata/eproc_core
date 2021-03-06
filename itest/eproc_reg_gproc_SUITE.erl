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
%%  Testcases for `eproc_reg_gproc` - a GProc based registry.
%%
-module(eproc_reg_gproc_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_register_fsm/1,
    test_registry_reset/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() ->
    [test_register_fsm, test_registry_reset].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:load(eproc_core),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    application:set_env(eproc_core, store, {eproc_store_ets, ref, []}),
    application:set_env(eproc_core, registry, {eproc_reg_gproc, ref, [[{load, false}]]}),
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
%%  Helper function.
%%
registry(Config) ->
    proplists:get_value(registry, Config).



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Check if register_fsm works. Also check if the registered PID can be
%%  resolved using `whereis_name/2` and message can be sent to it using `send/2`.
%%
test_register_fsm(Config) ->
    Registry = registry(Config),
    ok = eproc_registry:register_fsm(Registry, {inst, 1}, []),
    ok = eproc_registry:register_fsm(Registry, {inst, 1}, [{inst, 1}, {name, n}]),
    {ok, {via, eproc_reg_gproc, Inst1Id}} = eproc_registry:make_fsm_ref(Registry, {inst, 1}),
    {ok, {via, eproc_reg_gproc, Inst2Id}} = eproc_registry:make_fsm_ref(Registry, {inst, 2}),
    {ok, {via, eproc_reg_gproc, NameNId}} = eproc_registry:make_fsm_ref(Registry, {name, n}),
    TestPid = self(),
    TestPid     = eproc_reg_gproc:whereis_name(Inst1Id),
    undefined   = eproc_reg_gproc:whereis_name(Inst2Id),
    TestPid     = eproc_reg_gproc:whereis_name(NameNId),
    undefined   = eproc_reg_gproc:whereis_name(some),
    eproc_reg_gproc:send(Inst1Id, msg1),
    eproc_reg_gproc:send(NameNId, msg3),
    case catch eproc_reg_gproc:send(Inst2Id, msg2) of
        {'EXIT', _} -> ok
    end,
    ok = receive msg1 -> ok    after 100 -> error end,
    ok = receive msg3 -> ok    after 100 -> error end,
    ok = receive msg2 -> error after 100 -> ok    end,
    ok.


%%
%%  Check if registry reset works.
%%
test_registry_reset(_Config) ->
    {ok, Lamp} = eproc_fsm__lamp:create(),
    ok = eproc_fsm__lamp:toggle(Lamp),
    ok = eproc_reg_gproc:reset(),
    ok = timer:sleep(500),
    case catch eproc_fsm__lamp:toggle(Lamp) of
        {'EXIT', {noproc, _}} -> ok
    end,
    ok.


%%
%%  TODO: Start all the processes (including supervisors).
%%  TODO: Check if instances loaded on startup.
%%  TODO: Check if instance can be started using `whereis_name/2` and `send/2`.
%%


