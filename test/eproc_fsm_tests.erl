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
%%  Unit tests for `eproc_fsm`.
%%
-module(eproc_fsm_tests).
-compile([{parse_transform, lager_transform}]).
-define(DEBUG, true).
-include_lib("eunit/include/eunit.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include("eproc.hrl").


%%
%%  Helper function.
%%
unlink_kill(PIDs) when is_list(PIDs) ->
    lists:foreach(fun unlink_kill/1, PIDs);

unlink_kill(PID) ->
    true = unlink(PID),
    true = exit(PID, normal),
    ok.


%%
%%  Check if scope handing works.
%%
state_in_scope_test_() ->
    [
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({}, '_')),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a}, '_'  )),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a}, {'_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope(a,   {'_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope(a,   {'_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a}, a)),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a}, {a})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope(a,   a)),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope(a,   {a})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope(a,   {a, '_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b}, a)),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b}, '_')),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b}, {a, b})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b}, {a, '_'})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b}, {'_', b})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, a)),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, '_')),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, {a, {}, {}})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, {a, '_', '_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, {a, b,   '_'})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, {a, '_', c})),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope({a, b, c}, {a, b,   c})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({}, a)),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope(a, b)),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b, c}, b)),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b, c}, {b})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b, c}, {a, '_'})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b, c}, {b, '_', '_'})),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope({a, b, c}, {a, c, '_'})),
        % The following are for legacy support - list based states.
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([], [])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([a], [])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([a], [a])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([a, b], [a])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([a, b], [a, b])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([a, b], ['_', b])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([{a, [b], [c]}], [a])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{a, [], []}])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{a, '_', '_'}])),
        ?_assertMatch(true,  eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{a, [b], '_'}])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([], [a])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([a], [b])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([{a, [b], [c]}], [b])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{b}])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{b, []}])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{b, [], []}])),
        ?_assertMatch(false, eproc_fsm:is_state_in_scope([{a, [b], [c]}], [{a, [c], []}]))
    ].


is_state_valid_test_() ->
    [
        ?_assertMatch(true,  eproc_fsm:is_state_valid([])),
        ?_assertMatch(true,  eproc_fsm:is_state_valid([a, <<"b">>, 1])),
        ?_assertMatch(true,  eproc_fsm:is_state_valid([z, {a, [b, c], []}])),
        ?_assertMatch(true,  eproc_fsm:is_state_valid(1)),
        ?_assertMatch(true,  eproc_fsm:is_state_valid(<<"1">>)),
        ?_assertMatch(true,  eproc_fsm:is_state_valid({a})),
        ?_assertMatch(true,  eproc_fsm:is_state_valid({a, b})),
        ?_assertMatch(true,  eproc_fsm:is_state_valid({a, b, c})),
        ?_assertMatch(true,  eproc_fsm:is_state_valid({a, b, {c, x}})),
        ?_assertMatch(false, eproc_fsm:is_state_valid({{a, x}, b, {c, x}})),
        ?_assertMatch(false, eproc_fsm:is_state_valid([{a, [b], [c]}, z])),
        ?_assertMatch(false, eproc_fsm:is_state_valid([1.2]))
    ].

is_next_state_valid_test_() ->
    OrthP = {a, '_', '_', [w]},
    Orth1 = {a, [x], [y], [z]},
    Orth2 = {b, [i], [j], [k]},
    [
        ?_assertMatch(true,  eproc_fsm:is_next_state_valid([a, b, c])),
        ?_assertMatch(false, eproc_fsm:is_next_state_valid([])),
        ?_assertMatch(false, eproc_fsm:is_next_state_valid(12.3)),
        ?_assertMatch(true,  eproc_fsm:is_next_state_valid([Orth1])),
        ?_assertMatch(false, eproc_fsm:is_next_state_valid([OrthP])),
        ?_assertMatch(true,  eproc_fsm:is_next_state_valid([OrthP], [Orth1])),
        ?_assertMatch(false, eproc_fsm:is_next_state_valid([OrthP], [Orth2])),
        ?_assertMatch(false, eproc_fsm:is_next_state_valid([OrthP], [a, b, c]))
    ].


derive_next_state_test_() ->
    OrthP = {a, '_', '_', [w]},
    Orth1 = {a, [x], [y], [z]},
    Orth2 = {b, [i], [j], [k]},
    [
        ?_assertMatch({ok, {a, {b, c}}},            eproc_fsm:derive_next_state({a, {b, c}}, [])),
        ?_assertMatch({ok, Orth1},                  eproc_fsm:derive_next_state(Orth1,       {})),
        ?_assertMatch({ok, Orth1},                  eproc_fsm:derive_next_state(Orth1,       Orth2)),
        ?_assertMatch({ok, {a, [x], [y], [w]}},     eproc_fsm:derive_next_state(OrthP,       Orth1)),
        ?_assertMatch({error, {bad_state, '_'}},    eproc_fsm:derive_next_state(OrthP,       Orth2)),
        % The following are for legacy list based states.
        ?_assertMatch({ok, [a, b, c]},              eproc_fsm:derive_next_state([a, b, c], [])),
        ?_assertMatch({ok, [Orth1]},                eproc_fsm:derive_next_state([Orth1],   [])),
        ?_assertMatch({ok, [Orth1]},                eproc_fsm:derive_next_state([Orth1],   [Orth2])),
        ?_assertMatch({ok, [{a, [x], [y], [w]}]},   eproc_fsm:derive_next_state([OrthP],   [Orth1])),
        ?_assertMatch({error, {bad_state, '_'}},    eproc_fsm:derive_next_state([OrthP],   [Orth2]))
    ].


%%
%%  Test for eproc_fsm:create(Module, Args, Options)
%%
create_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{status = running, group = 17,  name = create_test, start_spec = undefined,     opts = [{n1, v1}]}) -> {ok, iid1};
        (_StoreRef, #instance{status = running, group = new, name = undefined,   start_spec = {default, []}, opts = []        }) -> {ok, iid2}
    end),
    ok = meck:expect(eproc_stats, instance_created, fun(_) -> ok end),
    {ok, {inst, iid1}} = eproc_fsm:create(eproc_fsm__void, {}, [{group, 17}, {name, create_test}, {n1, v1}]),
    {ok, {inst, iid2}} = eproc_fsm:create(eproc_fsm__void, {}, [{start_spec, {default, []}}]),
    ?assertEqual(2, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(2, meck:num_calls(eproc_fsm__void, init, [{}])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]).


%%
%%  Check if initial state if stored properly.
%%
create_state_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{args = {a, b}, curr_state = #inst_state{sname = [], sdata = {state, a, b}}}) -> {ok, iid1}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun ({A, B}) -> {ok, {state, A, B}} end),
    ok = meck:expect(eproc_stats, instance_created, fun(_) -> ok end),
    {ok, {inst, iid1}} = eproc_fsm:create(eproc_fsm__void, {a, b}, []),
    ?assertEqual(1, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, init, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]).



%%
%%  Check if new process can be started by instance id.
%%  Also checks, if attributes initialized.
%%
start_link_new_by_inst_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_fsm_attr, init, fun
        (100, [], 0, store, []) -> {ok, []}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm_attr, init, [100, [], 0, store, []])),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if new process can be started by name.
%%
start_link_new_by_name_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {name, N = start_link_by_name_test}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = N, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({name, start_link_by_name_test}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if existing process can be restarted.
%%  Also checks, if attributes initialized.
%%
start_link_existing_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 100}) ->
            {ok, #instance{
                inst_id = I, group = I, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], curr_state = #inst_state{
                    stt_id = 0,
                    sname = [some],
                    sdata = {state, b},
                    attr_last_nr = 2,
                    attrs_active = [
                        #attribute{attr_id = 1},
                        #attribute{attr_id = 2}
                    ]
                },
                status = running,
                created = os:timestamp()
            }}
    end),
    ok = meck:expect(eproc_fsm_attr, init, fun
        (100, [some], 2, store, [A = #attribute{attr_id = 1}, B = #attribute{attr_id = 2}]) -> {ok, [{A, undefined}, {B, undefined}]}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm_attr, init, '_')),
    ?assert(meck:called(eproc_fsm__void, init, [[some], {state, b}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [some], {state, b}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if functions id/0, group/0, name/0 works in an FSM process.
%%
start_link_get_id_group_name_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                inst_id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a}) ->
            ?assertEqual({ok, 1000}, eproc_fsm:id()),
            ?assertEqual({ok, 2000}, eproc_fsm:group()),
            ?assertEqual({ok, name}, eproc_fsm:name()),
            ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if runtime state initialization works.
%%  This will not theck, id runtime field is passed to other
%%  callbacks and not stored in DB. Other tests exists for that.
%%
start_link_init_runtime_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                inst_id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a, undefined}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a, undefined}) ->
            {ok, 3, z}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(meck:called(eproc_fsm__void, init, [[], {state, a, undefined}])),
    ?assert(meck:called(eproc_fsm__void, code_change, [state, [], {state, a, undefined}, undefined])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check, if FSM can be started with standard process registration.
%%
start_link_fsmname_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                inst_id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({local, start_link_fsmname_test}, {inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    ?assert(eproc_fsm:is_online(start_link_fsmname_test)),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if register option is handled properly.
%%  This test also checks, if registry is resolved.
%%
start_link_opts_register_test() ->
    GenInst = fun (I, N) -> #instance{
        inst_id = I, group = I, name = N, module = eproc_fsm__void,
        args = {a}, opts = [], status = running, created = os:timestamp(),
        curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
    } end,
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_registry, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun
        () -> {ok, store}
    end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) -> {ok, GenInst(I, name0)};
        (store, {inst, I = 1001}) -> {ok, GenInst(I, name1)};
        (store, {inst, I = 1002}) -> {ok, GenInst(I, name2)};
        (store, {inst, I = 1003}) -> {ok, GenInst(I, name3)};
        (store, {inst, I = 1004}) -> {ok, GenInst(I, name4)};
        (store, {inst, I = 1005}) -> {ok, GenInst(I, name5)};
        (store, {inst, I = 1006}) -> {ok, GenInst(I, undefined)}
    end),
    ok = meck:expect(eproc_registry, ref, fun
        () -> {ok, reg2}
    end),
    ok = meck:expect(eproc_registry, register_fsm, fun
        (_RegistryArgs, _InstId, _Refs) -> ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID0a} = eproc_fsm:start_link({inst, 1000}, [{register, none}]), % Registry will be not used.
    {ok, PID0b} = eproc_fsm:start_link({inst, 1000}, [{register, none}, {registry, reg1}]),
    {ok, PID1}  = eproc_fsm:start_link({inst, 1001}, [{register, id},   {registry, reg1}]),
    {ok, PID2}  = eproc_fsm:start_link({inst, 1002}, [{register, name}, {registry, reg1}]),
    {ok, PID3}  = eproc_fsm:start_link({inst, 1003}, [{register, both}, {registry, reg1}]),
    {ok, PID4}  = eproc_fsm:start_link({inst, 1004}, [{register, both}]), % Will use default
    {ok, PID5}  = eproc_fsm:start_link({inst, 1005}, [{registry, reg1}]), % Will register id and name.
    {ok, PID6}  = eproc_fsm:start_link({inst, 1006}, [{registry, reg1}]), % Will register id only.
    ?assert(eproc_fsm:is_online(PID0a)),
    ?assert(eproc_fsm:is_online(PID0b)),
    ?assert(eproc_fsm:is_online(PID1)),
    ?assert(eproc_fsm:is_online(PID2)),
    ?assert(eproc_fsm:is_online(PID3)),
    ?assert(eproc_fsm:is_online(PID4)),
    ?assert(eproc_fsm:is_online(PID5)),
    ?assert(eproc_fsm:is_online(PID6)),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [undefined, 1000, []])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1,      1000, []])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1, 1001, [{inst, 1001}]])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1, 1002, [{name, name2}]])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1, 1003, [{inst, 1003}, {name, name3}]])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg2, 1004, [{inst, 1004}, {name, name4}]])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1, 1005, [{inst, 1005}, {name, name5}]])),
    ?assertEqual(1, meck:num_calls(eproc_registry, register_fsm, [reg1, 1006, [{inst, 1006}]])),
    ?assertEqual(8, meck:num_calls(eproc_registry, register_fsm, '_')),
    ?assertEqual(1, meck:num_calls(eproc_registry, ref, [])),
    ?assert(meck:validate([eproc_store, eproc_registry, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_registry, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill([PID0a, PID0b, PID1, PID2, PID3, PID4, PID5, PID6]).


%%
%%  Check if restart options are handled properly.
%%  Also checks, if store is resolved from args.
%%
start_link_opts_limit_restarts_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, res, {series, some, 100, 1000, notify}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, res, 1) -> ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID1} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_restarts, {series, some, 100, 1000, notify}}]),
    {ok, PID2} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID1)),
    ?assert(eproc_fsm:is_online(PID2)),
    ?assertEqual(1, meck:num_calls(eproc_limits, setup, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, notify, '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill([PID1, PID2]).


%%
%%  Check if suspending on restart works.
%%
start_link_restart_suspend_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__void, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, undefined}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_store, set_instance_suspended, fun
        (store, {inst, InstId = 100}, {fault, restart_limit}) ->
            {ok, InstId}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, res, {series, some, 100, 1000, notify}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, res, 1) -> {reached, [res]}
    end),
    ok = meck:expect(eproc_limits, cleanup, fun
        ({'eproc_fsm$limits', 100}, res) -> ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_, _) -> ok end),
    OldTrapExit = erlang:process_flag(trap_exit, true),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_restarts, {series, some, 100, 1000, notify}}]),
    ?assert(receive {'EXIT', PID, normal}  -> true after 1000 -> false end),
    erlang:process_flag(trap_exit, OldTrapExit),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_store, load_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, set_instance_suspended, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, setup, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, notify, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, cleanup, '_')),
    ?assertEqual(0, meck:num_calls(eproc_fsm__void, '_', '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats]).


%%
%%  Check, if delay on restart works.
%%
start_link_restart_delay_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{sname = [], sdata = {state, undefined}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, res, {series, some, 100, 1000, {delay, 300}}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, res, 1) -> {delay, 300}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_restarts, {series, some, 100, 1000, {delay, 300}}}]),
    {TimeUS, _} = timer:tc(fun () -> ?assert(eproc_fsm:is_online(PID)) end),
    TimeMS = TimeUS div 1000,
    ?assertEqual(true, (TimeMS > 290) and (TimeMS < 500)),
    ?assertEqual(1, meck:num_calls(eproc_store, load_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, setup, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, notify, '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with final_state from the initial state.
%%
send_event_final_state_from_init_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{stt_id = 0, sname = [], sdata = {state, a}, attr_last_nr = 0, attrs_active = []}
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, 100, Transition = #transition{trn_id = TrnNr}, [#message{}]) ->
            #transition{
                trn_id       = 1,
                sname        = [done],
                sdata        = {state, a},
                timestamp    = {_, _, _},
                duration     = Duration,
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {100, 1, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                trn_messages = [],
                attr_last_nr = 0,
                attr_actions = [],
                inst_status  = completed
            } = Transition,
            ?assert(is_integer(Duration)),
            ?assert(Duration >= 0),
            {ok, 100, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_, _) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, done, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, done}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with final_state from an ordinary state.
%%
send_event_final_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 1, sname = [incrementing], sdata = {state, 5},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = completed
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_, _) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, close, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, close}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [closed]}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with next_state from the initial state.
%%
send_event_next_state_from_init_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, undefined},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 1}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, reset, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[], {event, reset}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {entry, []}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with next_state from an ordinary state.
%%
send_event_next_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 1,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, flip, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, flip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [decrementing]}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[decrementing], {entry, [incrementing]}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` crashes with same_state from the initial state.
%%
send_event_same_state_from_init_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, undefined},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr}, _Messages) ->
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([], {event, skip}, StateData) ->
            {same_state, StateData}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    unlink(PID),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, Reason} when Reason =/= normal -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(0, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]).


%%
%%  Check if `send_event/*` works with same_state from an ordinary state.
%%
send_event_same_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` works with `next_state` returned from the entry callback.
%%
send_event_entry_next_state_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 0,
                    sname = [],
                    sdata = {state, some},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 1}, [#message{}]) ->
            #transition{
                sname = [closed],
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}},
                trigger_resp = undefined,
                inst_status  = completed
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm__void:close(PID)),
    ?assert(receive {'DOWN', Mon, process, PID, Reason} when Reason == normal -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, close}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[closing], {entry, []}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[closing, cleanup], {entry, []}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__void, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]).


%%
%%  Check if `send_event/*` craches if reply_* is returned from the state transition.
%%
send_event_reply_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr}, _Messages) ->
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {event, get}, StateData) ->
            {reply_next, bad, [decrementing], StateData}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    unlink(PID),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, get, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, Reason} when Reason =/= normal -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(0, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]).


%%
%%  Check if runtime state is not stored to the DB.
%%
send_event_save_runtime_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, ref, fun () -> {ok, store} end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, I = 1000}) ->
            {ok, #instance{
                inst_id = I, group = 2000, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, a, this_is_empty},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([], {state, a, this_is_empty}) ->
            {ok, 3, not_empty_at_runtime}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr, sdata = {state, a, this_is_empty}}, [#message{}]) ->
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_, _) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 1000}, []),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm:send_event(PID, done, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, done}, {state, a, not_empty_at_runtime}])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `send_event/*` handles attributes correctly.
%%
send_event_handle_attrs_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm_attr, [passthrough]),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, flip, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, transition_start, '_')),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, transition_end, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm_attr, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm_attr, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if FSM is unregistered from the limit manager on a normal
%%  shutdown and is not unregistered on a crash.
%%
send_event_restart_unreg_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, IID}) ->
            {ok, #instance{
                inst_id = IID, group = 200, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, IID},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr}, [#message{}]) ->
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, res, {series, some, 100, 1000, notify}) -> ok;
        ({'eproc_fsm$limits', 200}, res, {series, some, 100, 1000, notify}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, res, 1) -> ok;
        ({'eproc_fsm$limits', 200}, res, 1) -> ok
    end),
    ok = meck:expect(eproc_limits, cleanup, fun
        ({'eproc_fsm$limits', 200}, res) -> ok
    end),
    ok = meck:expect(eproc_fsm__void, handle_state, fun
        ([], {event, done}, {state, 100}) ->
            meck:exception(error, some_error);
        ([], {event, done}, StateData = {state, 200}) ->
            {final_state, [done], StateData}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_,_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID1} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_restarts, {series, some, 100, 1000, notify}}]),
    {ok, PID2} = eproc_fsm:start_link({inst, 200}, [{store, store}, {limit_restarts, {series, some, 100, 1000, notify}}]),
    ?assert(eproc_fsm:is_online(PID1)),
    ?assert(eproc_fsm:is_online(PID2)),
    unlink(PID1),
    unlink(PID2),
    Mon1 = erlang:monitor(process, PID1),
    Mon2 = erlang:monitor(process, PID2),
    ?assertEqual(ok, eproc_fsm:send_event(PID1, done, [{source, {test, test}}])),
    ?assertEqual(ok, eproc_fsm:send_event(PID2, done, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon1, process, PID1, Reason} when Reason =/= normal-> true after 1000 -> false end),
    ?assert(receive {'DOWN', Mon2, process, PID2, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID1)),
    ?assertEqual(false, eproc_fsm:is_online(PID2)),
    ?assertEqual(0, meck:num_calls(eproc_limits, cleanup, [{'eproc_fsm$limits', 100}, res])),
    ?assertEqual(1, meck:num_calls(eproc_limits, cleanup, [{'eproc_fsm$limits', 200}, res])),
    ?assertEqual(1, meck:num_calls(eproc_limits, cleanup, '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__void, eproc_stats]),
    ok = unlink_kill([PID1, PID2]).


%%
%%  Check if process is suspended on transition, if requested by FSM implementation.
%%
send_event_suspend_by_user_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr = 2, inst_status = suspended, interrupts = Ints}, [#message{}]) ->
            [#interrupt{reason = {impl, some_realy_good_reason}}] = Ints,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {event, skip}, S) ->
            eproc_fsm:suspend(some_realy_good_reason),
            {next_state, [decrementing], S};
        ([incrementing], {exit, [decrementing]}, S) ->
            {ok, S};
        ([decrementing], {entry, [incrementing]}, S) ->
            {ok, S}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    OldTrapExit = erlang:process_flag(trap_exit, true),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    ?assert(receive {'EXIT', PID, normal}  -> true; AntMsg -> AntMsg after 1000 -> false end),
    erlang:process_flag(trap_exit, OldTrapExit),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, skip}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]).


%%
%%  Check if process is suspended on transition, if transition limit reached.
%%
send_event_limit_suspend_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr = 2, inst_status = suspended, interrupts = Ints}, [#message{}]) ->
            [#interrupt{reason = {fault, {limits, [{trn, [some]}]}}}] = Ints,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, trn, {series, some, 100, 0, notify}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, [{trn, 1}]) -> {reached, [{trn, [some]}]}
    end),
    ok = meck:expect(eproc_limits, cleanup, fun
        ({'eproc_fsm$limits', 100}, trn) -> ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_transitions, {series, some, 100, 0, notify}}]),
    ?assert(eproc_fsm:is_online(PID)),
    OldTrapExit = erlang:process_flag(trap_exit, true),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    ?assert(receive {'EXIT', PID, normal}  -> true; AntMsg -> AntMsg after 1000 -> false end),
    erlang:process_flag(trap_exit, OldTrapExit),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, setup, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, notify, '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__seq, eproc_stats]).


%%
%%  Check if process is delayed on transition, if transition limit reached.
%%
send_event_limit_delay_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_limits, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_limits, setup, fun
        ({'eproc_fsm$limits', 100}, trn, {series, some, 100, 0, {delay, 300}}) -> ok
    end),
    ok = meck:expect(eproc_limits, notify, fun
        ({'eproc_fsm$limits', 100}, [{trn, 1}]) -> {delay, 300}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}, {limit_transitions, {series, some, 100, 0, {delay, 300}}}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, skip, [{source, {test, test}}])),
    %%
    {TimeUS, _} = timer:tc(fun () -> ?assert(eproc_fsm:is_online(PID)) end),
    TimeMS = TimeUS div 1000,
    ?assertEqual(true, (TimeMS > 290) and (TimeMS < 500)),
    %%
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, skip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, setup, '_')),
    ?assertEqual(1, meck:num_calls(eproc_limits, notify, '_')),
    ?assert(meck:validate([eproc_store, eproc_limits, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_limits, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `self_send_event/1` works.
%%
self_send_event_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__void, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__void,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 0,
                    sname = [],
                    sdata = {state, some},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 1}, [#message{}, #message{}]) ->
            #transition{
                sname = [waiting],
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr};
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                sname = [done],
                trigger_type = self,
                trigger_msg  = #msg_ref{cid = {InstId, 1, _, recv}},
                trigger_resp = undefined,
                inst_status  = completed
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_,_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual(ok, eproc_fsm__void:self_done(PID)),
    ?assert(receive {'DOWN', Mon, process, PID, Reason} when Reason == normal -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[], {event, self_done}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[waiting], {entry, []}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[waiting], {self, done}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__void, handle_state, [[waiting], {exit, [done]}, '_'])),
    ?assertEqual(4, meck:num_calls(eproc_fsm__void, handle_state, '_')),
    ?assertEqual(2, meck:num_calls(eproc_store, add_transition, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, ['_', '_', #transition{trn_id = 1, _ = '_'}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, ['_', '_', #transition{trn_id = 2, _ = '_'}, '_'])),
    ?assert(meck:validate([eproc_store, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__void, eproc_stats]).


%%
%%  Check if `sync_send_event/*` works with reply_final from an ordinary state.
%%
sync_send_event_final_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1, sent}, peer = {test, test}},
                inst_status  = completed
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_completed, fun(_,_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, last, [{source, {test, test}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', last}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [closed]}, '_'])),
    ?assertEqual(2, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply_next from an ordinary state.
%%
sync_send_event_next_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1, sent}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, next, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', next}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [incrementing]}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {entry, [incrementing]}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply_same from an ordinary state.
%%
sync_send_event_same_state_from_ordinary_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1, sent}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, 5}, eproc_fsm:sync_send_event(PID, get, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `sync_send_event/*` works with reply/*.
%%
sync_send_event_reply_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}, #message{}]) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1, sent}, peer = {test, test}},
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {sync, From, get}, StateData) ->
            eproc_fsm:reply(From, {ok, something}),
            {same_state, StateData}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual({ok, something}, eproc_fsm:sync_send_event(PID, get, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {sync, '_', get}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if unknown messages are forwarded to the callback module.
%%
unknown_message_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1,
                    sname = [incrementing],
                    sdata = {state, 5},
                    attr_last_nr = 0,
                    attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, [#message{}]) ->
            #transition{
                trigger_type = info,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = undefined},
                trigger_resp = undefined,
                inst_status  = running
            } = Transition,
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {info, some_unknown_message}, StateData) ->
            {same_state, StateData}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    PID ! some_unknown_message,
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {info, some_unknown_message}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if send_create_event/* works.
%%  Also check if start_spec option is handled properly.
%%
send_create_event_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{status = running, opts = [{some, opt}]}) ->
            {ok, 127}
    end),
    ok = meck:expect(eproc_reg_gproc, send, fun
        ({new, reg_args, {inst, 127}, {mfa, ['$fsm_ref', some]}}, Event = {'$gen_cast', _}) ->
            Event
    end),
    ok = meck:expect(eproc_stats, instance_created, fun(_) -> ok end),
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, reg_args),
    ?assertEqual({ok, {inst, 127}}, eproc_fsm:send_create_event(eproc_fsm__void, {}, event1, [
        {start_spec, {mfa, ['$fsm_ref', some]}},
        {registry, Registry},
        {timeout, 12300},
        {source, {test, test}},
        {some, opt}
    ])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_reg_gproc, send, ['_', '_'])),
    ?assert(meck:validate([eproc_store, eproc_reg_gproc, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_reg_gproc, eproc_stats]).


%%
%%  Check if sync_send_create_event/* works.
%%
sync_send_create_event_test() ->
    Target = spawn(fun () ->
        receive
            {'$gen_call', From, _Event} ->
                gen_server:reply(From, {ok, 127, {127, 0, 1, sent}, reply1})
        end
    end),
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, add_instance, fun
        (_StoreRef, #instance{status = running, opts = []}) ->
            {ok, 127}
    end),
    ok = meck:expect(eproc_reg_gproc, whereis_name, fun
        ({new, reg_args, {inst, 127}, {default, []}}) ->
            Target
    end),
    ok = meck:expect(eproc_stats, instance_created, fun(_) -> ok end),
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, reg_args),
    ?assertEqual({ok, {inst, 127}, reply1}, eproc_fsm:sync_send_create_event(eproc_fsm__void, {}, event1, [
        {registry, Registry}
    ])),
    ?assertEqual(1, meck:num_calls(eproc_store, add_instance, '_')),
    ?assertEqual(1, meck:num_calls(eproc_reg_gproc, whereis_name, ['_'])),
    ?assert(meck:validate([eproc_store, eproc_reg_gproc, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_reg_gproc, eproc_stats]).


%%
%%  Check if `kill/*` works.
%%
kill_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, undefined},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, set_instance_killed, fun
        (store, {inst, InstId = 100}, #user_action{user = #user{uid = <<"SomeUser">>}, time = {_, _, _}, comment = <<"Hmm">>}) ->
            {ok, InstId};
        (store, {inst, unknown}, #user_action{}) ->
            {error, not_found}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_killed, fun(_,_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ok = meck:expect(eproc_reg_gproc, send, fun
        ({fsm, reg_args, {inst, 100}}, Event = {'$gen_cast', _}) ->
            PID ! Event
    end),
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, reg_args),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual({error, bad_ref},   eproc_fsm:kill(PID,             [{store, store}, {registry, Registry}])),
    ?assertEqual({error, not_found}, eproc_fsm:kill({inst, unknown}, [{store, store}, {registry, Registry}, {user, <<"SomeUser">>}])),
    ?assertEqual({ok, {inst, 100}},  eproc_fsm:kill({inst, 100},     [{store, store}, {registry, Registry}, {user, {<<"SomeUser">>, <<"Hmm">>}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(2, meck:num_calls(eproc_store, set_instance_killed, '_')),
    ?assertEqual(1, meck:num_calls(eproc_reg_gproc, send, '_')),
    ?assert(meck:validate([eproc_store, eproc_reg_gproc, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_reg_gproc, eproc_stats]).


%%
%% Check if suspend/* works.
%%
suspend_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {a}, opts = [], status = running, created = os:timestamp(), curr_state = #inst_state{
                    stt_id = 0, sname = [], sdata = {state, undefined},
                    attr_last_nr = 0, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, set_instance_suspended, fun
        (store, {inst, InstId = 100}, #user_action{user = #user{uid = <<"SomeUser">>}, time = {_, _, _}, comment = <<"Hmm">>}) ->
            {ok, InstId};
        (store, {inst, unknown}, #user_action{}) ->
            {error, not_found}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, instance_suspended, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ok = meck:expect(eproc_reg_gproc, send, fun
        ({fsm, reg_args, {inst, 100}}, Event = {'$gen_cast', _}) ->
            PID ! Event
    end),
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, reg_args),
    ?assert(eproc_fsm:is_online(PID)),
    Mon = erlang:monitor(process, PID),
    ?assertEqual({error, bad_ref},   eproc_fsm:suspend(PID,             [{store, store}, {registry, Registry}])),
    ?assertEqual({error, not_found}, eproc_fsm:suspend({inst, unknown}, [{store, store}, {registry, Registry}, {user, <<"SomeUser">>}])),
    ?assertEqual({ok, {inst, 100}},  eproc_fsm:suspend({inst, 100},     [{store, store}, {registry, Registry}, {user, {<<"SomeUser">>, <<"Hmm">>}}])),
    ?assert(receive {'DOWN', Mon, process, PID, normal} -> true after 1000 -> false end),
    ?assertEqual(false, eproc_fsm:is_online(PID)),
    ?assertEqual(2, meck:num_calls(eproc_store, set_instance_suspended, '_')),
    ?assertEqual(1, meck:num_calls(eproc_reg_gproc, send, '_')),
    ?assert(meck:validate([eproc_store, eproc_reg_gproc, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_reg_gproc, eproc_stats]).


%%
%%  Check if resume/* works without starting corresponding proceses.
%%
resume_no_start_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:expect(eproc_store, set_instance_resuming, fun
        (store, {inst, InstId = 101}, unchanged,      #user_action{}) -> {ok, InstId, {default, []}};
        (store, {inst, InstId = 102}, retry_last,     #user_action{}) -> {ok, InstId, {default, []}};
        (store, {inst, InstId = 103}, {set, a, b, c}, #user_action{}) -> {ok, InstId, {default, []}}
    end),
    {ok, {inst, 101}} = eproc_fsm:resume(resume_test_a, [{store, store}, {start, no}, {fsm_ref, {inst, 101}}, {state, unchanged}]),
    {ok, {inst, 102}} = eproc_fsm:resume(resume_test_b, [{store, store}, {start, no}, {fsm_ref, {inst, 102}}, {state, retry_last}]),
    {ok, {inst, 103}} = eproc_fsm:resume(resume_test_c, [{store, store}, {start, no}, {fsm_ref, {inst, 103}}, {state, {set, a, b, c}}]),
    ?assertEqual(1, meck:num_calls(eproc_store, set_instance_resuming, [store, {inst, 101}, '_', '_'])),
    ?assertEqual(1, meck:num_calls(eproc_store, set_instance_resuming, [store, {inst, 102}, '_', '_'])),
    ?assertEqual(1, meck:num_calls(eproc_store, set_instance_resuming, [store, {inst, 103}, '_', '_'])),
    ?assertEqual(3, meck:num_calls(eproc_store, set_instance_resuming, '_')),
    ?assert(meck:validate([eproc_store])),
    ok = meck:unload([eproc_store]).


%%
%%  Check if resume/* works including startup of the FSM in the cases when:
%%    * state
%%        * with original state (1).
%%        * with updated state (2).
%%        * with updated state, when new state is invalid (3).
%%        * with state name updated, and state data left unchanged (4).
%%    * start
%%        * as stored (1, 4)
%%        * as provided (2, 3, 4)
%%
resume_and_start_test() ->
    Opts = [{store, store}, {registry, registry}, {register, none}],
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_registry, [passthrough]),
    ok = meck:new(eproc_registry_mock, [non_strict]),
    ok = meck:new(eproc_fsm__void, []),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, set_instance_resuming, fun
        (store, {inst, InstId = 101}, unchanged,                         #user_action{}) -> {ok, InstId, {default, []}};
        (store, {inst, InstId = 102}, {set, [s2], d2, []},               #user_action{}) -> {ok, InstId, {default, []}};
        (store, {inst, InstId = 103}, {set, [s3], d3, []},               #user_action{}) -> {ok, InstId, {default, []}};
        (store, {inst, InstId = 104}, {set, [s4], undefined, undefined}, #user_action{}) -> {ok, InstId, {default, []}}
    end),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, InstId = 101}) ->
            {ok, #instance{
                inst_id = InstId, group = InstId, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = resuming, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [some], sdata = {state, b}, attr_last_nr = 2,
                    attrs_active = []
                },
                interrupt = #interrupt{
                    intr_id = undefined, status = active, suspended = os:timestamp(),
                    resumes = [#resume_attempt{
                        res_nr = 1, upd_sname = undefined, upd_sdata = undefined,
                        upd_script = undefined, resumed = #user_action{}
                    }]
                }
            }};
        (store, {inst, InstId = 102}) ->
            {ok, #instance{
                inst_id = InstId, group = InstId, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = resuming, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [some], sdata = {state, b}, attr_last_nr = 2,
                    attrs_active = []
                },
                interrupt = #interrupt{
                    intr_id = undefined, status = active, suspended = os:timestamp(),
                    resumes = [#resume_attempt{
                        res_nr = 1, upd_sname = [s2], upd_sdata = d2,
                        upd_script = [], resumed = #user_action{}
                    }]
                }
            }};
        (store, {inst, InstId = 103}) ->
            {ok, #instance{
                inst_id = InstId, group = InstId, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = resuming, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [some], sdata = {state, b}, attr_last_nr = 2,
                    attrs_active = []
                },
                interrupt = #interrupt{
                    intr_id = undefined, status = active, suspended = os:timestamp(),
                    resumes = [#resume_attempt{
                        res_nr = 1, upd_sname = [s3], upd_sdata = d3,
                        upd_script = [], resumed = #user_action{}
                    }]
                }
            }};
        (store, {inst, InstId = 104}) ->
            {ok, #instance{
                inst_id = InstId, group = InstId, name = name, module = eproc_fsm__void,
                args = {a}, opts = [], status = resuming, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [some], sdata = {state, b}, attr_last_nr = 2,
                    attrs_active = []
                },
                interrupt = #interrupt{
                    intr_id = undefined, status = active, suspended = os:timestamp(),
                    resumes = [#resume_attempt{
                        res_nr = 1, upd_sname = [s4], upd_sdata = undefined,
                        upd_script = undefined, resumed = #user_action{}
                    }]
                }
            }}
    end),
    ok = meck:expect(eproc_store, set_instance_resumed, fun
        (store, 101, 1) -> ok
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, #transition{trn_id = T, inst_status = running}, [#message{}]) -> {ok, InstId, T}
    end),
    ok = meck:expect(eproc_registry, make_new_fsm_ref, fun
        (registry, {inst, 101}, {default, [aaa]}) -> {ok, {via, eproc_registry_mock, 1}};
        (registry, {inst, 102}, {default, []})    -> {ok, {via, eproc_registry_mock, 2}};
        (registry, {inst, 103}, {default, []})    -> {ok, {via, eproc_registry_mock, 3}};
        (registry, {inst, 104}, {default, []})    -> {ok, {via, eproc_registry_mock, 4}}
    end),
    ok = meck:expect(eproc_registry_mock, whereis_name, fun
        (1) -> {ok, P} = eproc_fsm:start_link({local, resume_and_start_test_pid1}, {inst, 101}, Opts), unlink(P), P;
        (2) -> {ok, P} = eproc_fsm:start_link({local, resume_and_start_test_pid2}, {inst, 102}, Opts), unlink(P), P;
        (3) -> {ok, P} = eproc_fsm:start_link({local, resume_and_start_test_pid3}, {inst, 103}, Opts), unlink(P), P;
        (4) -> {ok, P} = eproc_fsm:start_link({local, resume_and_start_test_pid4}, {inst, 104}, Opts), unlink(P), P
    end),
    ok = meck:expect(eproc_fsm__void, code_change, fun
        (state, [some], {state, b}, undefined) -> {ok, [some], {state, b}};
        (state, [s2],   d2,         undefined) -> {ok, [s2],   d2};
        (state, [s3],   d3,         undefined) -> meck:exception(error, function_clause);
        (state, [s4],   {state, b}, undefined) -> {ok, [s4],   {state, b}}
    end),
    ok = meck:expect(eproc_fsm__void, init, fun
        ([some], {state, b}) -> ok;
        ([s2],   d2        ) -> ok;
        ([s4],   {state, b}) -> ok
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, {inst, 101}}      = eproc_fsm:resume(resume_and_start_test_1, [{start, {default, [aaa]}}, {fsm_ref, {inst, 101}}, {state, unchanged} | Opts]),
    {ok, {inst, 102}}      = eproc_fsm:resume(resume_and_start_test_2, [{start, yes}, {fsm_ref, {inst, 102}}, {state, {set, [s2], d2, []}} | Opts]),
    {error, resume_failed} = eproc_fsm:resume(resume_and_start_test_3, [{start, yes}, {fsm_ref, {inst, 103}}, {state, {set, [s3], d3, []}} | Opts]),
    {ok, {inst, 104}}      = eproc_fsm:resume(resume_and_start_test_4, [{start, yes}, {fsm_ref, {inst, 104}}, {state, {set, [s4], undefined, undefined}} | Opts]),
    exit(whereis(resume_and_start_test_pid1), normal),
    exit(whereis(resume_and_start_test_pid2), normal),
    exit(whereis(resume_and_start_test_pid4), normal),
    ?assert(meck:validate([eproc_store, eproc_registry, eproc_registry_mock, eproc_fsm__void, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_registry, eproc_registry_mock, eproc_fsm__void, eproc_stats]).


%%
%%  Check if resume/* fails when:
%%    * FSM is online
%%    * FSM is offline but not suspended.
%%
resume_reject_test() ->
    Target = spawn_link(fun () ->
        receive {'$gen_call', From, {'eproc_fsm$is_online'}} -> gen_server:reply(From, true) end
    end),
    ok = meck:new(eproc_store, []),
    ok = meck:expect(eproc_store, set_instance_resuming, fun
        (store, {inst, 102}, _, _) -> {error, running}
    end),
    {error, running} = eproc_fsm:resume(Target,             [{store, store}, {start, no}, {fsm_ref, {inst, 101}}]),
    {error, running} = eproc_fsm:resume(resume_reject_test, [{store, store}, {start, no}, {fsm_ref, {inst, 102}}]),
    ?assert(meck:validate([eproc_store])),
    ok = meck:unload([eproc_store]).


%%
%%  Check if `register_message/4` works in the case of outgoing messages (sent by FSM).
%%
register_outgoing_message_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__seq, [passthrough]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__seq,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [incrementing],
                    sdata = {state, 5}, attr_last_nr = 1, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, Messages) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = undefined,
                trn_messages = TrnMsgs,
                inst_status  = running
            } = Transition,
            ?assertEqual(1, length([ ok || #message{body = flip} <- Messages ])),
            ?assertEqual(1, length([ ok || #message{body = msg1} <- Messages ])),
            ?assertEqual(1, length([ ok || #message{body = msg2} <- Messages ])),
            ?assertEqual(1, length([ ok || #message{body = msg3} <- Messages ])),
            ?assertEqual(4, length(Messages)),
            ?assertEqual(3, length(TrnMsgs)),
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__seq, handle_state, fun
        ([incrementing], {event, flip}, St) ->
            {ok, IID} = eproc_fsm:id(),
            Src = {inst, IID},
            Dst = {some, out},
            Now = {1, 2, 3},
            {ok, MID1} = eproc_fsm:register_sent_msg(Src, Dst, undefined, <<"msg1">>, msg1, Now),
            {ok, MID2} = eproc_fsm:register_sent_msg(Src, Dst, undefined, <<"msg2">>, msg2, Now),
            {ok, MID3} = eproc_fsm:register_resp_msg(Src, Dst, MID2, undefined, <<"msg3">>, msg3, Now),
            ?assertEqual({100, 2, 2, sent}, MID1),
            ?assertEqual({100, 2, 3, sent}, MID2),
            ?assertEqual({100, 2, 4, recv}, MID3),
            {next_state, [decrementing], St};
        ([incrementing], {exit,  [decrementing]}, St) -> {ok, St};
        ([decrementing], {entry, [incrementing]}, St) -> {ok, St}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(ok, eproc_fsm:send_event(PID, flip, [{source, {test, test}}])),
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {event, flip}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[incrementing], {exit, [decrementing]}, '_'])),
    ?assertEqual(1, meck:num_calls(eproc_fsm__seq, handle_state, [[decrementing], {entry, [incrementing]}, '_'])),
    ?assertEqual(3, meck:num_calls(eproc_fsm__seq, handle_state, '_')),
    ?assertEqual(1, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__seq, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__seq, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `register_*_msg/*` works in the case of incoming messages.
%%
register_incoming_message_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:new(eproc_fsm__mock, [non_strict]),
    ok = meck:new(eproc_stats, []),
    ok = meck:expect(eproc_store, load_instance, fun
        (store, {inst, 100}) ->
            {ok, #instance{
                inst_id = 100, group = 200, name = name, module = eproc_fsm__mock,
                args = {}, opts = [], status = running, created = os:timestamp(),
                curr_state = #inst_state{
                    stt_id = 1, sname = [sa], sdata = {state, 5},
                    attr_last_nr = 1, attrs_active = []
                }
            }}
    end),
    ok = meck:expect(eproc_store, add_transition, fun
        (store, InstId, Transition = #transition{trn_id = TrnNr = 2}, Messages) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {InstId, TrnNr, 0, recv}, peer = {test, test}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1, sent}, peer = {test, test}},
                trn_messages = [],
                inst_status  = running
            } = Transition,
            ?assertEqual(1, length([ ok || #message{body = get} <- Messages ])),
            ?assertEqual(1, length([ ok || #message{body = res} <- Messages ])),
            ?assertEqual(2, length(Messages)),
            {ok, InstId, TrnNr};
        (store, InstId, Transition = #transition{trn_id = TrnNr = 3}, Messages) ->
            #transition{
                trigger_type = sync,
                trigger_msg  = #msg_ref{cid = {200,    15,    20, recv}, peer = {inst, 200}},
                trigger_resp = #msg_ref{cid = {InstId, TrnNr, 1,  sent}, peer = {inst, 200}},
                trn_messages = [],
                inst_status  = running
            } = Transition,
            ?assertEqual(1, length([ ok || #message{body = get} <- Messages ])),
            ?assertEqual(1, length([ ok || #message{body = res} <- Messages ])),
            ?assertEqual(2, length(Messages)),
            {ok, InstId, TrnNr};
        (store, InstId, Transition = #transition{trn_id = TrnNr = 4}, Messages) ->
            #transition{
                trigger_type = event,
                trigger_msg  = #msg_ref{cid = {200, 15, 21, recv}, peer = {inst, 200}},
                trigger_resp = undefined,
                trn_messages = [],
                inst_status  = running
            } = Transition,
            ?assertEqual(1, length([ ok || #message{body = set} <- Messages ])),
            ?assertEqual(1, length(Messages)),
            {ok, InstId, TrnNr}
    end),
    ok = meck:expect(eproc_fsm__mock, init, 2, ok),
    ok = meck:expect(eproc_fsm__mock, code_change, 4, {ok, [sa], {state, 5}}),
    ok = meck:expect(eproc_fsm__mock, handle_state, fun
        ([sa], {sync, _, get}, St) -> {reply_same, res, St};
        ([sa], {event, set},   St) -> {next_state, [sb], St};
        ([sa], {exit,  [sb]},  St) -> {ok, St};
        ([sb], {entry, [sa]},  St) -> {ok, St}
    end),
    ok = meck:expect(eproc_stats, instance_started, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, transition_completed, fun(_) -> ok end),
    ok = meck:expect(eproc_stats, message_created, fun(_) -> ok end),
    %% Execute the test.
    {ok, PID} = eproc_fsm:start_link({inst, 100}, [{store, store}]),
    ?assert(eproc_fsm:is_online(PID)),
    ?assertEqual(res, eproc_fsm:sync_send_event(PID, get, [{source, {test, test}}])),
    erlang:put('eproc_fsm$msg_regs', {msg_regs, 200, 15, 20, []}),
    ?assertEqual(res, eproc_fsm:sync_send_event(PID, get, [{source, {inst, 200}}])),
    ?assertEqual(ok,  eproc_fsm:send_event(PID, set, [{source, {inst, 200}}])),
    %%  Proceed with assertions.
    ?assertEqual(true, eproc_fsm:is_online(PID)),
    {msg_regs, 200, 15, 22, Regs} = erlang:erase('eproc_fsm$msg_regs'),
    ?assertEqual(2, length(Regs)),
    io:format("XXX: ~p~n", [Regs]),
    ?assertEqual(1, length([ ok || {msg_reg, {inst, 100},       {200, 15, 20, sent}, get, <<"get">>, {_, _, _}, {100, 3, 1, recv}, res, <<"res">>, {_, _, _}} <- Regs])),
    ?assertEqual(1, length([ ok || {msg_reg, {inst, undefined}, {200, 15, 21, sent}, set, <<"set">>, {_, _, _}, undefined, undefined, undefined, undefined}   <- Regs])),
    ?assertEqual(3, meck:num_calls(eproc_store, add_transition, '_')),
    ?assert(meck:validate([eproc_store, eproc_fsm__mock, eproc_stats])),
    ok = meck:unload([eproc_store, eproc_fsm__mock, eproc_stats]),
    ok = unlink_kill(PID).


%%
%%  Check if `resolve_start_spec/2` works.
%%
resolve_start_spec_test_() -> [
    ?_assertEqual(
        {start_link_args, [{inst, i}, [opts]]},
        eproc_fsm:resolve_start_spec({inst, i}, {default, [opts]})
    ),
    ?_assertEqual(
        {start_link_mfa, {m, f, [a1, {inst, a}, a3]}},
        eproc_fsm:resolve_start_spec({inst, a}, {mfa, {m, f, [a1, '$fsm_ref', a3]}})
    )].


%%
%%  Check, if `resolve_event_type/2` works.
%%
resolve_event_type_test_() -> [
        ?_assertEqual(<<"asd">>, eproc_fsm:resolve_event_type(event, asd)),
        ?_assertEqual(<<"dsd">>, eproc_fsm:resolve_event_type(event, <<"dsd">>)),
        ?_assertEqual(<<"fsa">>, eproc_fsm:resolve_event_type(event, {fsa, asd, [[]]})),
        ?_assertEqual(<<"[a]">>, eproc_fsm:resolve_event_type(event, [a]))
    ].


%%
%%  Check, if `resolve_event_type_const/3` works.
%%
resolve_event_type_const_test_() -> [
        ?_assertEqual(<<"uuu">>, eproc_fsm:resolve_event_type_const(sync,  <<"uuu">>, asd)),
        ?_assertEqual(<<"uuz">>, eproc_fsm:resolve_event_type_const(sync,  uuz,       asd)),
        ?_assertEqual(<<"asd">>, eproc_fsm:resolve_event_type_const(reply, <<"uuu">>, asd))
    ].


%%
%%  Check if orthogonal with a trigger of the form `{entry, _}` works.
%%
orthogonal_entry_test() ->
    meck:new(eproc_fsm__mock, [non_strict]),
    meck:expect(eproc_fsm__mock, handle_state, fun
        ({orth, a1,  '_'}, {entry, from}, SD) -> {ok,                          [a1 | SD]};
        ({orth, '_', b1 }, {entry, from}, SD) -> {next_state, {orth, '_', b2}, [b1 | SD]};
        ({orth, '_', b2 }, {entry, from}, SD) -> {next_state, {orth, '_', b3}, [b2 | SD]};
        ({orth, '_', b3 }, {entry, from}, SD) -> {same_state,                  [b3 | SD]}
    end),
    ?assertEqual(
        {next_state, {orth, a1, b3}, [b3, b2, b1, a1]},
        eproc_fsm:orthogonal({orth, a1, b1}, {entry, from}, [], eproc_fsm__mock)
    ),
    ?assert(meck:validate(eproc_fsm__mock)),
    ok = meck:unload(eproc_fsm__mock).


% TODO: Test handling of crashes in callbacks in sync and async calls.


