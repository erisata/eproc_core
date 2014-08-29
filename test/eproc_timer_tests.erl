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

-module(eproc_timer_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Check if attribute action specs are registered correctly for the `set` functions.
%%
mocked_set_test() ->
    ok = meck:new(eproc_fsm),
    ok = meck:new(eproc_fsm_attr),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, undefined}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}};
        ({inst, some}, {timer, undefined}, undefined, msg2, {_, _, _}) -> {ok, {i, t, m2, sent}};
        ({inst, some}, {timer, some},      undefined, msg3, {_, _, _}) -> {ok, {i, t, m3, sent}}
    end),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, undefined, {timer, 1000, {i, t, m1, sent}, msg1}, next) -> ok;
        (eproc_timer, undefined, {timer, 1000, {i, t, m2, sent}, msg2}, []) -> ok;
        (eproc_timer, some,      {timer, 1000, {i, t, m3, sent}, msg3}, []) -> ok
    end),
    ok = eproc_timer:set(1000, msg1),
    ok = eproc_timer:set(1000, msg2, []),
    ok = eproc_timer:set(some, 1000, msg3, []),
    ?assertEqual(3, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assertEqual(3, meck:num_calls(eproc_fsm_attr, action, '_')),
    ?assert(meck:validate([eproc_fsm, eproc_fsm_attr])),
    ok = meck:unload([eproc_fsm, eproc_fsm_attr]).


%%
%%  Check if attribute actuib spec is registered correctly for the `cancel` function.
%%
mocked_cancel_test() ->
    ok = meck:new(eproc_fsm_attr),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, aaa, {timer, remove}) -> ok
    end),
    ok = eproc_timer:cancel(aaa),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, action, '_')),
    ?assert(meck:validate(eproc_fsm_attr)),
    ok = meck:unload(eproc_fsm_attr).


%%
%%  Check if existing timers are restarted on init.
%%
init_restart_test() ->
    OldNow = erlang:now(),
    receive after 200 -> ok end,
    Attr1 = #attribute{ % In the past.
        module = eproc_timer, name = undefined, scope = [],
        data = {data, OldNow, 100, {i, t, m1, sent}, msg1},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    Attr2 =  #attribute{ % In the future.
        module = eproc_timer, name = undefined, scope = [],
        data = {data, erlang:now(), 100, {i, t, m2, sent}, msg2},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    {ok, _State} = eproc_fsm_attr:init(0, [], 0, store, [Attr1, Attr2]),
    ?assert(receive _TimerMsg1 -> true after 200 -> false end),
    ?assert(receive _TimerMsg2 -> true after 400 -> false end).


%%
%%  Test creation of a timer using real eproc_fsm_attr module.
%%
set_create_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, undefined}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
    end),
    {ok, State1} = eproc_fsm_attr:init(0, [], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [], State1),
    ok = eproc_timer:set(100, msg1),
    {ok, _Actions3, _LastAttrId3, _State3} = eproc_fsm_attr:transition_end(0, 0, [], State2),
    ?assert(receive _TimerMsg -> true after 200 -> false end),
    ?assertEqual(1, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assert(meck:validate([eproc_fsm])),
    ok = meck:unload([eproc_fsm]).


%%
%%  Test updating of a timer using real eproc_fsm_attr module.
%%
set_update_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, some}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
    end),
    {ok, State1} = eproc_fsm_attr:init(0, [], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [], State1),
    ok = eproc_timer:set(some, 100, msg1, []),
    {ok, _Actions3, _LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [], State3),
    ok = eproc_timer:set(some, 300, msg1, []),
    {ok, _Actions5, _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(0, 0, [], State4),
    ?assert(receive _TimerMsg1 -> false after 200 -> true end),
    ?assert(receive _TimerMsg2 -> true after 600 -> false end),
    ?assertEqual(2, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assert(meck:validate([eproc_fsm])),
    ok = meck:unload([eproc_fsm]).


%%
%%  Test updating of a timer using real eproc_fsm_attr module.
%%
cancel_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, some}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
    end),
    {ok, State1} = eproc_fsm_attr:init(0, [], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [], State1),
    ok = eproc_timer:set(some, 100, msg1, []),
    {ok, _Actions3, _LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [], State3),
    ok = eproc_timer:cancel(some),
    {ok, _Actions5, _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(0, 0, [], State4),
    ?assert(receive _TimerMsg -> false after 300 -> true end),
    ?assertEqual(1, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assert(meck:validate([eproc_fsm])),
    ok = meck:unload([eproc_fsm]).


%%
%%  Test if a timer is removed by scope.
%%  Also test scope `next`.
%%
remove_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, some}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
    end),
    {ok, State1} = eproc_fsm_attr:init(0, [first], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [first], State1),
    ok = eproc_timer:set(some, 100, msg1, next),
    {ok, _Actions3, _LastAttrId5, State3} = eproc_fsm_attr:transition_end(0, 0, [second], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [second], State3),
    {ok, _Actions5, _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(0, 0, [third], State4),
    ?assert(receive _TimerMsg -> false after 300 -> true end),
    ?assertEqual(1, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assert(meck:validate([eproc_fsm])),
    ok = meck:unload([eproc_fsm]).


%%
%%  Test if a message fired by a timer is recognized.
%%
event_fired_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, some}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
    end),
    {ok, State1} = eproc_fsm_attr:init(0, [first], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [first], State1),
    ok = eproc_timer:set(some, {100, ms}, msg1, next),
    {ok, _Actions3, _LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [second], State2),
    ok = receive TimerMsg -> ok after 300 -> TimerMsg = undefined end,
    ?assertMatch({trigger, _State4, #trigger_spec{}, _Action}, eproc_fsm_attr:event(0, TimerMsg, State3)),
    ?assertEqual(1, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assert(meck:validate([eproc_fsm])),
    ok = meck:unload([eproc_fsm]).


%%
%%  Check if `duration_to_ms/1` works.
%%
duration_to_ms_test_() -> [
    ?_assertEqual(2, eproc_timer:duration_to_ms({2, ms})),
    ?_assertEqual(2000, eproc_timer:duration_to_ms({2, s})),
    ?_assertEqual(2000, eproc_timer:duration_to_ms({2, sec})),
    ?_assertEqual(120000, eproc_timer:duration_to_ms({2, min})),
    ?_assertEqual(7200000, eproc_timer:duration_to_ms({2, hour})),
    ?_assertEqual(172800000, eproc_timer:duration_to_ms({2, day})),
    ?_assertEqual(1209600000, eproc_timer:duration_to_ms({2, week})),
    ?_assertEqual(5184000000, eproc_timer:duration_to_ms({2, month})),
    ?_assertEqual(63072000000, eproc_timer:duration_to_ms({2, year})),
    ?_assertEqual(2010, eproc_timer:duration_to_ms([{2, s}, {10, ms}]))
    ].


%%
%%  Check if `timestamp_before/2` and `timestamp_after/2` work.
%%
timestamp_before_after_test_() ->
    Now = os:timestamp(),
    Before1s = eproc_timer:timestamp_before({1, sec},   Now),
    Before1h = eproc_timer:timestamp_before({1, hour},  Now),
    Before1d = eproc_timer:timestamp_before({1, day},   Now),
    Before1m = eproc_timer:timestamp_before({1, month}, Now),
    Before1y = eproc_timer:timestamp_before({1, year},  Now),
    After1s = eproc_timer:timestamp_after({1, sec},   Now),
    After1h = eproc_timer:timestamp_after({1, hour},  Now),
    After1d = eproc_timer:timestamp_after({1, day},   Now),
    After1m = eproc_timer:timestamp_after({1, month}, Now),
    After1y = eproc_timer:timestamp_after({1, year},  Now),
    [
        ?_assertEqual(eproc_timer:duration_to_ms({2, sec}  ) * 1000, timer:now_diff(After1s, Before1s)),
        ?_assertEqual(eproc_timer:duration_to_ms({2, hour} ) * 1000, timer:now_diff(After1h, Before1h)),
        ?_assertEqual(eproc_timer:duration_to_ms({2, day}  ) * 1000, timer:now_diff(After1d, Before1d)),
        ?_assertEqual(eproc_timer:duration_to_ms({2, month}) * 1000, timer:now_diff(After1m, Before1m)),
        ?_assertEqual(eproc_timer:duration_to_ms({2, year} ) * 1000, timer:now_diff(After1y, Before1y))
    ].

%%
%%  Check if `timestamp/1` works.
%%
timestamp_test_() ->
    [
        ?_assertEqual(eproc_timer:timestamp(null), undefined),
        ?_assertEqual(eproc_timer:timestamp(undefined), undefined),
        ?_assertEqual(eproc_timer:timestamp({{2014,8,29},{11,14,0}}), {1409, 310840, 0})
    ].


