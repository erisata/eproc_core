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
        scope = [], data = {data, a, undefined}, from = from_trn
    },
    {ok, _State} = eproc_fsm_attr:init(100, [], 0, store, [Attr]).


%%
%%  Check, if describing works.
%%
describe_test() ->
    Attr = #attribute{
        module = eproc_router, name = {key, a},
        scope = [], data = {data, a, undefined}, from = from_trn
    },
    {ok, [
        {key, a}
    ]} = eproc_fsm_attr:describe(Attr, all).


%%
%%  Check if attribute creation works.
%%
add_key_test() ->
    ok = meck:new(eproc_store),
    ok = meck:expect(eproc_store, attr_task, [
        {[store, eproc_router, {key_sync, key3, iid, false}], meck:seq([{ok, ref3},  {ok, undefined}])},
        {[store, eproc_router, {key_sync, key5, iid, true }], meck:seq([{ok, ref51}, {ok, undefined}, {ok, ref52}])},
        {[store, eproc_router, {key_sync, key6, iid, true }], {error, exists}},
        {[store, eproc_router, {key_sync, key7, iid, false}], {ok, ref7}}
    ]),
    erlang:put('eproc_fsm$id', iid),
    {ok, State1} = eproc_fsm_attr:init(100, [], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(100, 0, [first], State1),
    ok = eproc_router:add_key(key1, next),
    ok = eproc_router:add_key(key2, '_'),
    ok = eproc_router:add_key(key3, '_',  [sync]),
    ok = eproc_router:add_key(key4, '_',  [uniq]),
    ok = eproc_router:add_key(key4, next, [uniq]),
    ok = eproc_router:add_key(key5, '_',  [sync, uniq]),
    ok = eproc_router:add_key(key5, next, [sync, uniq]),
    {error, exists} = eproc_router:add_key(key6, '_', [sync, uniq]),    % Already registered by different fsm
    ok = eproc_router:add_key(key7, '_',  []),
    ok = eproc_router:add_key(key7, '_',  [sync]),
    {ok, AttrActions3, _LastAttrId3, State3} = eproc_fsm_attr:transition_end(100, 0, second, State2),
    {ok, State4} = eproc_fsm_attr:transition_start(100, 0, second, State3),
    {ok, AttrActions5, _LastAttrId5, State5} = eproc_fsm_attr:transition_end(100, 0, third, State4),
    {ok, State6} = eproc_fsm_attr:transition_start(100, 0, third, State5),
    ok = eproc_router:add_key(key2, next),
    ok = eproc_router:add_key(key3, '_',  [sync]),
    ok = eproc_router:add_key(key4, next, [uniq]),
    ok = eproc_router:add_key(key5, '_',  [sync, uniq]),
    {error, exists} = eproc_router:add_key(key6, '_', [sync, uniq]),    % Already registered by different fsm
    {ok, AttrActions7, _LastAttrId7, _State7} = eproc_fsm_attr:transition_end(100, 0, fourth, State6),
    erlang:erase('eproc_fsm$id'),
    DefAction = #attr_action{module = eproc_router, needs_store = true},
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 1, action = {create, key1, second, {data, key1, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 2, action = {create, key2, '_',    {data, key2, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 3, action = {create, key3, '_',    {data, key3, ref3     }}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 4, action = {create, key4, '_',    {data, key4, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 4, action = {update,       second, {data, key4, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 5, action = {create, key5, '_',    {data, key5, ref51    }}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 5, action = {update,       second, {data, key5, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 6, action = {create, key7, '_',    {data, key7, undefined}}})),
    ?assertThat(AttrActions3, contains_member(DefAction#attr_action{attr_nr = 6, action = {update,       '_',    {data, key7, ref7     }}})),
    ?assertThat(AttrActions3, has_length(9)),
    ?assertThat(AttrActions5, contains_member(DefAction#attr_action{attr_nr = 1, action = {remove, {scope, third}}})),
    ?assertThat(AttrActions5, contains_member(DefAction#attr_action{attr_nr = 4, action = {remove, {scope, third}}})),
    ?assertThat(AttrActions5, contains_member(DefAction#attr_action{attr_nr = 5, action = {remove, {scope, third}}})),
    ?assertThat(AttrActions5, has_length(3)),
    ?assertThat(AttrActions7, contains_member(DefAction#attr_action{attr_nr = 2, action = {update,       fourth, {data, key2, undefined}}})),
    ?assertThat(AttrActions7, contains_member(DefAction#attr_action{attr_nr = 3, action = {update,       '_',    {data, key3, undefined}}})),
    ?assertThat(AttrActions7, contains_member(DefAction#attr_action{attr_nr = 7, action = {create, key4, fourth, {data, key4, undefined}}})),
    ?assertThat(AttrActions7, contains_member(DefAction#attr_action{attr_nr = 8, action = {create, key5, '_',    {data, key5, ref52    }}})),
    ?assertThat(AttrActions7, has_length(4)),
    ?assertThat(meck:num_calls(eproc_store, attr_task, '_'), is(8)),
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


