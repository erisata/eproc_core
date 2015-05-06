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

-module(eproc_timer_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").


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
        ({inst, some}, {timer, undefined}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}};
        ({inst, some}, {timer, undefined}, undefined, _, msg2, {_, _, _}) -> {ok, {i, t, m2, sent}};
        ({inst, some}, {timer, some},      undefined, _, msg3, {_, _, _}) -> {ok, {i, t, m3, sent}};
        ({inst, some}, {timer, other},     undefined, _, msg4, {_, _, _}) -> {ok, {i, t, m4, sent}}
    end),
    ok = meck:expect(eproc_fsm, resolve_event_type, fun
        (timer, _Message) -> <<"timer_msg">>
    end),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, undefined, {timer, 1000, {_, _, _}, {i, t, m1, sent}, _, msg1}, next) -> ok;
        (eproc_timer, undefined, {timer, 1000, {_, _, _}, {i, t, m2, sent}, _, msg2}, []) -> ok;
        (eproc_timer, some,      {timer, 1000, {_, _, _}, {i, t, m3, sent}, _, msg3}, []) -> ok;
        (eproc_timer, other,     {timer, _,    {_, _, _}, {i, t, m4, sent}, _, msg4}, []) -> ok
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
    OldNow = os:timestamp(),
    ok = timer:sleep(200),
    Attr1 = #attribute{ % In the past.
        module = eproc_timer, name = undefined, scope = [],
        data = {data, OldNow, 100, {i, t, m1, sent}, <<"msg1">>, msg1},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    Attr2 =  #attribute{ % In the future.
        module = eproc_timer, name = undefined, scope = [],
        data = {data, OldNow, 400, {i, t, m2, sent}, <<"msg1">>, msg2},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    {ok, _State} = eproc_fsm_attr:init(0, [], 0, store, [Attr1, Attr2]),
    ?assert(receive _TimerMsg1 -> true  after 100 -> false end),    % This should be fired immediatelly.
    ?assert(receive _TimerMsg2 -> false after 150 -> true  end),    % This should be fired within 200 ms
    ?assert(receive _TimerMsg2 -> true  after 150 -> false end).    %   from the eproc_fsm_attr:init/5.


%%
%%  Check, if describing works.
%%
describe_test() ->
    Now = os:timestamp(),
    Dura = 100,
    Fire = eproc_timer:timestamp_after(Dura, Now),
    Attr = #attribute{ % In the past.
        module = eproc_timer, name = undefined, scope = [],
        data = {data, Now, Dura, msg1, {i, t, m1, sent}, <<"msg1">>},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    {ok, [
        {start_time,    Now},
        {delay_ms,      100},
        {fire_time,     Fire},
        {event_cid,     {i, t, m1, sent}},
        {event_type,    <<"msg1">>},
        {event_body,    msg1}
    ]} = eproc_fsm_attr:describe(Attr, all).


%%
%%  Test creation of a timer using real eproc_fsm_attr module.
%%
set_create_test() ->
    ok = meck:new(eproc_fsm, [passthrough]),
    ok = meck:expect(eproc_fsm, id, fun
        () -> {ok, some}
    end),
    ok = meck:expect(eproc_fsm, register_sent_msg, fun
        ({inst, some}, {timer, undefined}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
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
        ({inst, some}, {timer, some}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
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
        ({inst, some}, {timer, some}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
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
        ({inst, some}, {timer, some}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
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
        ({inst, some}, {timer, some}, undefined, _, msg1, {_, _, _}) -> {ok, {i, t, m1, sent}}
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
%%  Check if `duration_format/2` works.
%%
duration_parse_test_() ->
    Dur01 = eproc_timer:duration_parse("P2Y", iso8601),
    Dur02 = eproc_timer:duration_parse("P2Y3M", iso8601),
    Dur03 = eproc_timer:duration_parse("P2YT3M", iso8601),
    Dur04 = eproc_timer:duration_parse("PT3M15S", iso8601),
    Dur05 = eproc_timer:duration_parse("PT3M1.S", iso8601),
    Dur06 = eproc_timer:duration_parse("PT2.5S", iso8601),
    Dur07 = eproc_timer:duration_parse("PT3.50S", iso8601),
    Dur08 = eproc_timer:duration_parse("PT4.500S", iso8601),
    Dur09 = eproc_timer:duration_parse("PT5.05S", iso8601),
    Dur10 = eproc_timer:duration_parse("PT6.005S", iso8601),
    Dur11 = eproc_timer:duration_parse("PT7.123S", iso8601),
    Dur12 = eproc_timer:duration_parse("PT8.4567S", iso8601),
    Dur13 = eproc_timer:duration_parse("P24Y11M31DT12H23M34.567S", iso8601),

    % Preparation of results for checks
    Dur05a = lists:filter(fun
        ({_, min}) -> false;
        ({_, s}) -> false;
        (_) -> true
    end, Dur05),

    [
        ?_assertEqual([{2,year}], Dur01),
        ?_assertThat(Dur02, contains_member({2,year})),
        ?_assertThat(Dur02, contains_member({3,month})),
        ?_assertThat(Dur02, has_length(2)),
        ?_assertThat(Dur03, contains_member({2,year})),
        ?_assertThat(Dur03, contains_member({3,min})),
        ?_assertThat(Dur03, has_length(2)),
        ?_assertThat(Dur04, contains_member({3,min})),
        ?_assertThat(Dur04, contains_member({15,s})),
        ?_assertThat(Dur04, has_length(2)),
        ?_assertThat(Dur05, contains_member({3,min})),
        ?_assertThat(Dur05, contains_member({1,s})),
        ?_assertThat(Dur05a, any_of([is([{0,ms}]), is([])])),
        ?_assertThat(Dur05, any_of([has_length(2), has_length(3)])),
        ?_assertThat(Dur06, contains_member({2,s})),
        ?_assertThat(Dur06, contains_member({500,ms})),
        ?_assertThat(Dur06, has_length(2)),
        ?_assertThat(Dur07, contains_member({3,s})),
        ?_assertThat(Dur07, contains_member({500,ms})),
        ?_assertThat(Dur07, has_length(2)),
        ?_assertThat(Dur08, contains_member({4,s})),
        ?_assertThat(Dur08, contains_member({500,ms})),
        ?_assertThat(Dur08, has_length(2)),
        ?_assertThat(Dur09, contains_member({5,s})),
        ?_assertThat(Dur09, contains_member({50,ms})),
        ?_assertThat(Dur09, has_length(2)),
        ?_assertThat(Dur10, contains_member({6,s})),
        ?_assertThat(Dur10, contains_member({5,ms})),
        ?_assertThat(Dur10, has_length(2)),
        ?_assertThat(Dur11, contains_member({7,s})),
        ?_assertThat(Dur11, contains_member({123,ms})),
        ?_assertThat(Dur11, has_length(2)),
        ?_assertThat(Dur12, contains_member({8,s})),
        ?_assertThat(Dur12, contains_member({456,ms})),
        ?_assertThat(Dur12, has_length(2)),
        ?_assertThat(Dur13, contains_member({24,year})),
        ?_assertThat(Dur13, contains_member({11,month})),
        ?_assertThat(Dur13, contains_member({31,day})),
        ?_assertThat(Dur13, contains_member({12,hour})),
        ?_assertThat(Dur13, contains_member({23,min})),
        ?_assertThat(Dur13, contains_member({34,s})),
        ?_assertThat(Dur13, contains_member({567,ms})),
        ?_assertThat(Dur13, has_length(7))
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

