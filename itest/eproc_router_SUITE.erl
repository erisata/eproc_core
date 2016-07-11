%/--------------------------------------------------------------------
%| Copyright 2013-2016 Erisata, UAB (Ltd.)
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
%%  Testcases for `eproc_router`.
%%
-module(eproc_router_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    test_async_multi_key/1,
    test_async_uniq_key/1,
    test_sync_multi_key/1,
    test_sync_uniq_key/1,
    test_sync_async_key/1
]).
-define(namespaced_types, ok).
-include_lib("common_test/include/ct.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include("eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_async_multi_key,
    test_async_uniq_key,
    test_sync_multi_key,
    test_sync_uniq_key,
    test_sync_async_key
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


%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Test, if asynchronously adding non unique key works.
%%
test_async_multi_key(_Config) ->
    % Initialisation
    {ok, IRef1 = {inst, IID1}} = eproc_fsm__router_key:new(),
    {ok, IRef2 = {inst, IID2}} = eproc_fsm__router_key:new(),
    IID12Sorted = lists:sort([IID1, IID2]),
    % Tests
    Key = key_async_multi,
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', []), is({ok, {ok, []}})),        % Key for the first instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', []), is({ok, {ok, [IID1]}})),    % Same key for the same instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef2, Key, '_', []), is({ok, {ok, [IID1]}})),    % Same key for different instance
    {ok, Result01} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result01), is(IID12Sorted)),
    ok = eproc_fsm__router_key:next_state(IRef1),
    {ok, Result02} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result02), is(IID12Sorted)),
    {ok, {ok, Result03}} = eproc_fsm__router_key:add_key(IRef1, Key, next, []),                 % Same key for the same instance, scope changed
    ?assertThat(lists:sort(Result03), is(IID12Sorted)),
    {ok, Result04} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result04), is(IID12Sorted)),
    ok = eproc_fsm__router_key:next_state(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID2]})),
    % Cleanup
    ok = eproc_fsm__router_key:finalise(IRef1),
    ok = eproc_fsm__router_key:finalise(IRef2),
    ?assertThat(eproc_router:lookup(Key), is({ok, []})),
    ok.


%%
%%  Test, if asynchronously adding unique key works.
%%  NOTE: unique keys can only be added synchroniously -> nothing to test here.
%%
test_async_uniq_key(_Config) ->
    ok.


%%
%%  Test, if synchronously adding non unique key works.
%%
test_sync_multi_key(_Config) ->
    % Initialisation
    {ok, IRef1 = {inst, IID1}} = eproc_fsm__router_key:new(),
    {ok, IRef2 = {inst, IID2}} = eproc_fsm__router_key:new(),
    IID12Sorted = lists:sort([IID1, IID2]),
    % Tests
    Key = key_async_multi,
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', [sync]), is({ok, {ok, [IID1]}})),    % Key for the first instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', [sync]), is({ok, {ok, [IID1]}})),    % Same key for the same instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    {ok, {ok, Result01}} = eproc_fsm__router_key:add_key(IRef2, Key, '_', [sync]),
    ?assertThat(lists:sort(Result01), is(IID12Sorted)),                                             % Same key for different instance
    {ok, Result02} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result02), is(IID12Sorted)),
    ok = eproc_fsm__router_key:next_state(IRef1),
    {ok, Result03} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result03), is(IID12Sorted)),
    {ok, {ok, Result04}} = eproc_fsm__router_key:add_key(IRef1, Key, next, [sync]),                 % Same key for the same instance, scope changed
    ?assertThat(lists:sort(Result04), is(IID12Sorted)),
    {ok, Result05} = eproc_router:lookup(Key),
    ?assertThat(lists:sort(Result05), is(IID12Sorted)),
    ok = eproc_fsm__router_key:next_state(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID2]})),
    % Cleanup
    ok = eproc_fsm__router_key:finalise(IRef1),
    ok = eproc_fsm__router_key:finalise(IRef2),
    ?assertThat(eproc_router:lookup(Key), is({ok, []})),
    ok.


%%
%%  Test, if synchronously adding unique key works.
%%
test_sync_uniq_key(_Config) ->
    % Initialisation
    {ok, IRef1 = {inst, IID1}} = eproc_fsm__router_key:new(),
    {ok, IRef2               } = eproc_fsm__router_key:new(),
    % Tests
    Key = key_async_multi,
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', [sync, uniq]), is({ok, {ok, [IID1]}})),  % Key for the first instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, '_', [sync, uniq]), is({ok, {ok, [IID1]}})),  % Same key for the same instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef2, Key, '_', [sync, uniq]), is({error, exists})),     % Same key for different instance
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ok = eproc_fsm__router_key:next_state(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ?assertThat(eproc_fsm__router_key:add_key(IRef1, Key, next, [sync, uniq]), is({ok, {ok, [IID1]}})), % Same key for the same instance, scope changed
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ok = eproc_fsm__router_key:next_state(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, []})),
    % Cleanup
    ok = eproc_fsm__router_key:finalise(IRef1),
    ok = eproc_fsm__router_key:finalise(IRef2),
    ?assertThat(eproc_router:lookup(Key), is({ok, []})),
    ok.


%%
%%  Test, if adding same key asynchronously and then synchronously in the same transition works.
%%
test_sync_async_key(_Config) ->
    % Initialisation
    {ok, IRef1 = {inst, IID1}} = eproc_fsm__router_key:new(),
    % Tests
    Key = key_sync_async,
    ?assertThat(eproc_fsm__router_key:add_keys(IRef1, [{Key, '_', []}, {Key, '_', [sync]}]), is([{ok, {ok, []}}, {ok, {ok, [IID1]}}])),
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    ok = eproc_fsm__router_key:next_state(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, [IID1]})),
    % Cleanup
    ok = eproc_fsm__router_key:finalise(IRef1),
    ?assertThat(eproc_router:lookup(Key), is({ok, []})),
    ok.


