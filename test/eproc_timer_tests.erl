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
    Now = os:timestamp(),
    ok = meck:new(eproc_fsm),
    ok = meck:new(eproc_fsm_attr),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, undefined}, undefined, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}};
        ({inst, some}, {timer, undefined}, undefined, msg2, {_, _, _}) -> {ok, {i, t, m2, sent}};
        ({inst, some}, {timer, some},      undefined, msg3, {_, _, _}) -> {ok, {i, t, m3, sent}};
        ({inst, some}, {timer, other},     undefined, msg4, {_, _, _}) -> {ok, {i, t, m4, sent}}
    end),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, undefined, {timer, 1000, {_, _, _}, {i, t, m1, sent}, msg1}, next) -> ok;
        (eproc_timer, undefined, {timer, 1000, {_, _, _}, {i, t, m2, sent}, msg2}, []) -> ok;
        (eproc_timer, some,      {timer, 1000, {_, _, _}, {i, t, m3, sent}, msg3}, []) -> ok;
        (eproc_timer, other,     {timer, _,    {_, _, _}, {i, t, m4, sent}, msg4}, []) -> ok
    end),
    ok = eproc_timer:set(1000, msg1),
    ok = eproc_timer:set(1000, msg2, []),
    ok = eproc_timer:set(some, 1000, msg3, []),
    ok = eproc_timer:set(other, eproc_timer:timestamp_after({1, min}, Now), msg4, []), % Fire at exact timestamp.
    ?assertEqual(4, meck:num_calls(eproc_fsm, register_sent_msg, '_')),
    ?assertEqual(4, meck:num_calls(eproc_fsm_attr, action, '_')),
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
%%  Check if `duration_format/2` works.
%%
duration_format_test_() -> [
    ?_assertEqual(<<"PT0S">>, eproc_timer:duration_format([], iso8601)),
    ?_assertEqual(<<"PT2M3.456S">>, eproc_timer:duration_format(123456, iso8601)),
    ?_assertEqual(<<"PT0.002S">>, eproc_timer:duration_format({2, ms}, iso8601)),
    ?_assertEqual(<<"PT2S">>, eproc_timer:duration_format({2, s}, iso8601)),
    ?_assertEqual(<<"PT2S">>, eproc_timer:duration_format({2, sec}, iso8601)),
    ?_assertEqual(<<"PT2M">>, eproc_timer:duration_format({2, min}, iso8601)),
    ?_assertEqual(<<"PT2H">>, eproc_timer:duration_format({2, hour}, iso8601)),
    ?_assertEqual(<<"P2D">>, eproc_timer:duration_format({2, day}, iso8601)),
    ?_assertEqual(<<"P14D">>, eproc_timer:duration_format({2, week}, iso8601)),
    ?_assertEqual(<<"P60D">>, eproc_timer:duration_format({2, month}, iso8601)),
    ?_assertEqual(<<"P730D">>, eproc_timer:duration_format({2, year}, iso8601)),
    ?_assertEqual(<<"PT2.010S">>, eproc_timer:duration_format([{2, s}, {10, ms}], iso8601)),
    ?_assertEqual(<<"P5DT0.123S">>, eproc_timer:duration_format([{5, day}, {123, ms}], iso8601)),
    ?_assertEqual(<<"PT5M45S">>, eproc_timer:duration_format({345, s}, iso8601))
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
        ?_assertEqual(eproc_timer:timestamp(null,      utc), undefined),
        ?_assertEqual(eproc_timer:timestamp(undefined, utc), undefined),
        ?_assertEqual(eproc_timer:timestamp({{2014,8,29},{11,14,0}, 125}, utc), {1409, 310840, 125}),
        ?_assertEqual(eproc_timer:timestamp({{2014,8,29},{11,14,0}     }, utc), {1409, 310840,   0}),
        ?_assertEqual(eproc_timer:timestamp( {2014,8,29},                 utc), {1409, 270400,   0})
    ].

%%
%%  Check if `timestamp_diff/2` works.
%%
timestamp_diff_test_() ->
    TS1 = eproc_timer:timestamp({{2014,8,29},{11,14,0}      }, utc),
    TS2 = eproc_timer:timestamp({{2014,8,29},{11,14,0},    3}, utc),
    TS3 = eproc_timer:timestamp({{2014,8,29},{11,14,0}, 3000}, utc),
    TS4 = eproc_timer:timestamp({{2014,8,29},{11,14,3}      }, utc),
    TS5 = eproc_timer:timestamp({{2014,8,29},{14,17,3}      }, utc),
    TS6 = eproc_timer:timestamp({{2014,9,30},{14,17,3}, 4004}, utc),
    [
        ?_assertEqual(eproc_timer:timestamp_diff(undefined, undefined), undefined),
        ?_assertEqual(eproc_timer:timestamp_diff(undefined, {0, 0, 0}), undefined),
        ?_assertEqual(eproc_timer:timestamp_diff({0, 0, 0}, undefined), undefined),
        ?_assertEqual(eproc_timer:timestamp_diff(TS1, TS1), {0, ms}),
        ?_assertEqual(eproc_timer:timestamp_diff(TS2, TS1), {3, us}),
        ?_assertEqual(eproc_timer:timestamp_diff(TS3, TS1), {3, ms}),
        ?_assertEqual(eproc_timer:timestamp_diff(TS4, TS1), {3, sec}),
        ?_assertEqual(eproc_timer:timestamp_diff(TS5, TS1), [{3, hour}, {3, min}, {3, sec}]),
        ?_assertEqual(eproc_timer:timestamp_diff(TS6, TS1), [{32, day}, {3, hour}, {3, min}, {3, sec}, {4, ms}, {4, us}])
    ].


%%
%%  Check if `timestamp_format/2` works.
%%  TODO: This (and other) tests asume current locale to be +3:00. Remove this assumption.
%%
timestamp_format_test_() ->
    TS0 = eproc_timer:timestamp({{2014,9,02},{14,17,3}}, local),
    TS1 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4004}, local),
    TS2 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4004}, utc),
    [
        ?_assertEqual(<<"2014-09-02T11:17:03.000000Z">>, eproc_timer:timestamp_format(TS0, {iso8601, utc})),
        ?_assertEqual(<<"2014-09-02T11:17:03.004004Z">>, eproc_timer:timestamp_format(TS1, {iso8601, utc})),
        ?_assertEqual(<<"2014-09-02T14:17:03.004004Z">>, eproc_timer:timestamp_format(TS2, {iso8601, utc, us})),
        ?_assertEqual(<<"2014-09-02T14:17:03.004Z">>,    eproc_timer:timestamp_format(TS2, {iso8601, utc, ms})),
        ?_assertEqual(<<"2014-09-02T14:17:03Z">>,        eproc_timer:timestamp_format(TS2, {iso8601, utc, sec}))
    ].


%%
%%  Check if `timestamp_parse/2` works.
%%
timestamp_parse_test_() ->
    TS0 = eproc_timer:timestamp({{2014,9,02},{14,17,3}},       utc),
    TS1 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4000}, utc),
    TS2 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4004}, utc),
    TS3 = eproc_timer:timestamp({{2014,9,02},{14,17,3}},       local),
    TS4 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4000}, local),
    TS5 = eproc_timer:timestamp({{2014,9,02},{14,17,3}, 4004}, local),
    [
        ?_assertEqual(TS0, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03Z">>,        iso8601)),
        ?_assertEqual(TS1, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03.004Z">>,    iso8601)),
        ?_assertEqual(TS2, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03.004004Z">>, iso8601)),
        ?_assertEqual(TS3, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03">>,         iso8601)),
        ?_assertEqual(TS4, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03.004">>,     iso8601)),
        ?_assertEqual(TS5, eproc_timer:timestamp_parse(<<"2014-09-02T14:17:03.004004">>,  iso8601))
    ].

