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
        module = eproc_router, name = {key, a},
        scope = [], data = {data, a}, from = from_trn
    },
    {ok, _State} = eproc_fsm_attr:init(100, [], 0, store, [Attr]).


%%
%%  Check if attribute creation works.
%%
add_key_test() ->
    ok = meck:new(eproc_store),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_router, {key_sync, key3, iid, false}) -> {ok, ref3};
        (store, eproc_router, {key_sync, key5, iid, true }) -> {ok, ref5}
    end),
    erlang:put('eproc_fsm$id', iid),
    {ok, State1} = eproc_fsm_attr:init(100, [], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(100, 0, [first], State1),
    ok = eproc_router:add_key(key1, next),
    ok = eproc_router:add_key(key2, []),
    ok = eproc_router:add_key(key3, [], [sync]),
    ok = eproc_router:add_key(key4, [], [uniq]),
    ok = eproc_router:add_key(key5, [], [sync, uniq]),
    {ok, AttrActions3, _LastAttrId3, State3} = eproc_fsm_attr:transition_end(100, 0, [second], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(100, 0, [second], State3),
    {ok, AttrActions5, _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(100, 0, [third], State4),
    erlang:erase('eproc_fsm$id'),
    DefAction = #attr_action{module = eproc_router, needs_store = true},
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 1, action = {create, undefined, [second], {data, key1, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 2, action = {create, undefined, [],       {data, key2, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 3, action = {create, undefined, [],       {data, key3, ref3     }}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 4, action = {create, undefined, [],       {data, key4, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 5, action = {create, undefined, [],       {data, key5, ref5     }}})),
    ?assertThat(AttrActions3, has_length(5)),
    ?assertThat(AttrActions5, contains_member(DefAction#attr_action{attr_nr = 1, action = {remove, {scope, [third]}}})),
    ?assertThat(AttrActions5, has_length(1)),
    ?assertThat(meck:num_calls(eproc_store, attr_task, '_'), is(2)),
    ?assert(meck:validate(eproc_store)),
    ok = meck:unload(eproc_store).


%%
%%  Check, if lookup works.
%%
lookup_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_router, {lookup, my_key}) -> {ok, [a, b, c]}
    end),
    ?assertThat(eproc_router:lookup(my_key, [{store, store}]), is({ok, [a, b, c]})),
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
    Opts1 = [{store, store}],
    Opts2 = [{store, store}, {uniq, false}],
    ?assertThat(eproc_router:lookup_send(key1, Opts1, fun lookup_send_test_mod:test_fun/1), is({error, multiple})),
    ?assertThat(eproc_router:lookup_send(key2, Opts1, fun lookup_send_test_mod:test_fun/1), is(ok)),
    ?assertThat(eproc_router:lookup_send(key3, Opts1, fun lookup_send_test_mod:test_fun/1), is({error, not_found})),
    ?assertThat(eproc_router:lookup_send(key1, Opts2, fun lookup_send_test_mod:test_fun/1), is(ok)),
    ?assertThat(eproc_router:lookup_send(key2, Opts2, fun lookup_send_test_mod:test_fun/1), is(ok)),
    ?assertThat(eproc_router:lookup_send(key3, Opts2, fun lookup_send_test_mod:test_fun/1), is(ok)),
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
    Opts = [{store, store}],
    ?assertThat(eproc_router:lookup_sync_send(key1, Opts, fun lookup_send_test_mod:test_fun/1), is({error, multiple})),
    ?assertThat(eproc_router:lookup_sync_send(key2, Opts, fun lookup_send_test_mod:test_fun/1), is(res_d)),
    ?assertThat(eproc_router:lookup_sync_send(key3, Opts, fun lookup_send_test_mod:test_fun/1), is({error, not_found})),
    ?assertThat(meck:num_calls(lookup_send_test_mod, test_fun, [{inst, d}]), is(1)),
    ?assert(meck:validate([eproc_store, lookup_send_test_mod])),
    ok = meck:unload([eproc_store, lookup_send_test_mod]).


