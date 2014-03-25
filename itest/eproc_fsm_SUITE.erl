%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
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
-module(eproc_fsm_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_seq/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_seq
    ].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:load(eproc_core),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_reg_gproc, []}),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = application:ensure_all_started(eproc_core),
    {ok, Store} = eproc_registry:ref(),
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

store(Config) ->
    proplists:get_value(store, Config).



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Test functions of the SEQ FSM.
%%
test_seq(Config) ->
    {ok, Seq} = eproc_fsm__seq:new(),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    {ok, 2} = eproc_fsm__seq:next(Seq),
    {ok, 2} = eproc_fsm__seq:get(Seq),
    ok = eproc_fsm__seq:flip(Seq),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    {ok, 0} = eproc_fsm__seq:next(Seq),
    ok = eproc_fsm__seq:flip(Seq),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    ok = eproc_fsm__seq:reset(Seq),
    ok = eproc_fsm__seq:skip(Seq),
    ok = eproc_fsm__seq:skip(Seq),
    true = eproc_fsm:is_online(Seq),
    {ok, 2} = eproc_fsm__seq:last(Seq),
    false = eproc_fsm:is_online(Seq),
    ok.



