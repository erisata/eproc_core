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

-module(eproc_router_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").


%%
%%  Check if init works.
%%
init_test() ->
    Attr = #attribute{
        inst_id = iid, module = eproc_router, name = {key, a},
        scope = [], data = {data, a}, from = from_trn
    },
    {ok, _State} = eproc_fsm_attr:init([], 0, store, [Attr]).


%%
%%  Check if attribute creation works.
%%
%%  TODO: sync, uniq
%%
add_key_test() ->
    {ok, State1} = eproc_fsm_attr:init([], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [first], State1),
    ok = eproc_router:add_key(key1, next),
    ok = eproc_router:add_key(key2, []),
    {ok, [_, _], _LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [second], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [second], State3),
    {ok, [_], _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(0, 0, [third], State4).


%%
%%  Check, if lookup works.
%%
lookup_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_router, {lookup, my_key}) -> {ok, [a, b, c]}
    end),
    {ok, Router} = eproc_router:setup([], [{store, store}]),
    ?assertThat(eproc_router:lookup(Router, my_key), is({ok, [a, b, c]})),
    ?assert(meck:validate([eproc_store])),
    ok = meck:unload([eproc_store]).


%%
%%  Check if lookup_send works in the cases when uniq=true/false.
%%
lookup_send_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(lookup_send_test_mod, [non_strict]),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_router, {lookup, key1}) -> {ok, [a, b, c]};
        (store, eproc_router, {lookup, key2}) -> {ok, [d]};
        (store, eproc_router, {lookup, key3}) -> {ok, []}
    end),
    ok = meck:expect(lookup_send_test_mod, test_fun, fun
        (_FsmRef) -> ok
    end),
    {ok, R1} = eproc_router:setup([], [{store, store}]),
    {ok, R2} = eproc_router:setup([], [{store, store}, {uniq, false}]),
    ?assertThat(eproc_router:lookup_send(R1, key1, fun lookup_send_test_mod:test_fun/1), is({error, multiple})),
    ?assertThat(eproc_router:lookup_send(R1, key2, fun lookup_send_test_mod:test_fun/1), is(noreply)),
    ?assertThat(eproc_router:lookup_send(R1, key3, fun lookup_send_test_mod:test_fun/1), is({error, not_found})),
    ?assertThat(eproc_router:lookup_send(R2, key1, fun lookup_send_test_mod:test_fun/1), is(noreply)),
    ?assertThat(eproc_router:lookup_send(R2, key2, fun lookup_send_test_mod:test_fun/1), is(noreply)),
    ?assertThat(eproc_router:lookup_send(R2, key3, fun lookup_send_test_mod:test_fun/1), is(noreply)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, '_'), is(5)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, a}]), is(1)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, b}]), is(1)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, c}]), is(1)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, d}]), is(2)),
    ?assert(meck:validate([eproc_store, lookup_send_test_mod])),
    ok = meck:unload([eproc_store, lookup_send_test_mod]).


%%
%%  Check if lookup_sync_send works.
%%
lookup_sync_send_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(lookup_send_test_mod, [non_strict]),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_router, {lookup, key1}) -> {ok, [a, b, c]};
        (store, eproc_router, {lookup, key2}) -> {ok, [d]};
        (store, eproc_router, {lookup, key3}) -> {ok, []}
    end),
    ok = meck:expect(lookup_send_test_mod, test_fun, fun
        ({inst, d}) -> res_d
    end),
    {ok, R1} = eproc_router:setup([], [{store, store}]),
    {ok, R2} = eproc_router:setup([], [{store, store}, {uniq, false}]),
    ?assertThat(eproc_router:lookup_sync_send(R1, key1, fun lookup_send_test_mod:test_fun/1), is({error, multiple})),
    ?assertThat(eproc_router:lookup_sync_send(R1, key2, fun lookup_send_test_mod:test_fun/1), is({reply, res_d})),
    ?assertThat(eproc_router:lookup_sync_send(R1, key3, fun lookup_send_test_mod:test_fun/1), is({error, not_found})),
    ?assertThat(eproc_router:lookup_sync_send(R2, key1, fun lookup_send_test_mod:test_fun/1), is({error, multiple})),
    ?assertThat(eproc_router:lookup_sync_send(R2, key2, fun lookup_send_test_mod:test_fun/1), is({reply, res_d})),
    ?assertThat(eproc_router:lookup_sync_send(R2, key3, fun lookup_send_test_mod:test_fun/1), is({error, not_found})),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, '_'), is(2)),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, d}]), is(2)),
    ?assert(meck:validate([eproc_store, lookup_send_test_mod])),
    ok = meck:unload([eproc_store, lookup_send_test_mod]).


%%
%%  TODO
%%
send_event_test() ->
    ?assert(todo).


%%
%%  TODO
%%
sync_send_event_test() ->
    ?assert(todo).


