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

-module(eproc_fsm_attr_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Initialization test with empty state (no attrs).
%%
init_empty_test() ->
    {ok, _State} = eproc_fsm_attr:init([], 0, []).


%%
%%  Initialization test with several active attrs.
%%
init_mock_test() ->
    meck:new(eproc_fsm_attr_test1, [non_strict]),
    meck:new(eproc_fsm_attr_test2, [non_strict]),
    meck:expect(eproc_fsm_attr_test1, init, fun([A, B]) -> {ok, [{A, state}, {B, state}]} end),
    meck:expect(eproc_fsm_attr_test2, init, fun([C]) -> {ok, [{C, state}]} end),
    {ok, _State} = eproc_fsm_attr:init([], 0, [
        #attribute{module = eproc_fsm_attr_test1, scope = []},
        #attribute{module = eproc_fsm_attr_test1, scope = []},
        #attribute{module = eproc_fsm_attr_test2, scope = []}
    ]),
    true = meck:validate([eproc_fsm_attr_test1, eproc_fsm_attr_test2]),
    meck:unload([eproc_fsm_attr_test1, eproc_fsm_attr_test2]).


%%
%%  Test if transition is initialized properly.
%%
transition_start_test() ->
    meck:new(eproc_fsm_attr_test1, [non_strict]),
    meck:expect(eproc_fsm_attr_test1, init, fun([A]) -> {ok, [{A, state}]} end),
    {ok, State} = eproc_fsm_attr:init([], 0, [#attribute{module = eproc_fsm_attr_test1, scope = []}]),
    ?assertMatch({ok, State}, eproc_fsm_attr:transition_start(0, 0, [], State)),
    ?assertEqual([], erlang:get('eproc_fsm_attr$actions')),
    true = meck:validate([eproc_fsm_attr_test1]),
    meck:unload([eproc_fsm_attr_test1]).

%%
%%  Test if transition is completed properly.
%%
transition_end_empty_test() ->
    meck:new(eproc_fsm_attr_test1, [non_strict]),
    meck:expect(eproc_fsm_attr_test1, init, fun([A]) -> {ok, [{A, state}]} end),
    {ok, State} = eproc_fsm_attr:init([], 0, [#attribute{attr_id = 1, module = eproc_fsm_attr_test1, scope = []}]),
    ?assertMatch({ok, State}, eproc_fsm_attr:transition_start(0, 0, [], State)),
    ?assertMatch({ok, [], State}, eproc_fsm_attr:transition_end(0, 0, [], State)),
    ?assertEqual(undefined, erlang:get('eproc_fsm_attr$actions')),
    true = meck:validate([eproc_fsm_attr_test1]),
    meck:unload([eproc_fsm_attr_test1]).


%%
%%  Test if clenup by scope works.
%%
transition_end_remove_test() ->
    meck:new(eproc_fsm_attr__void),
    meck:expect(eproc_fsm_attr__void, init, fun([A, B]) -> {ok, [{A, state}, {B, state}]} end),
    meck:expect(eproc_fsm_attr__void, handle_removed, fun(_A, _S) -> ok end),
    {ok, State} = eproc_fsm_attr:init([], 0, [
        #attribute{module = eproc_fsm_attr__void, scope = []},
        #attribute{module = eproc_fsm_attr__void, scope = [some]}
    ]),
    {ok, State} = eproc_fsm_attr:transition_start(0, 0, [some], State),
    {ok, [Action], _State2} = eproc_fsm_attr:transition_end(0, 0, [], State),
    ?assertMatch(#attr_action{action = {remove, {scope, []}}}, Action),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr__void, handle_removed, '_')),
    ?assert(meck:validate([eproc_fsm_attr__void])),
    meck:unload([eproc_fsm_attr__void]).


%%
%%  Test if attribute is created, updated and removed.
%%
action_success_test() ->
    Mod = eproc_fsm_attr__void,
    meck:new(Mod),
    meck:expect(Mod, init, fun([A, B]) -> {ok, [{A, state}, {B, state}]} end),
    meck:expect(Mod, handle_updated, fun
        (#attribute{name = a, data = 100}, state, del, undefined) -> {remove, deleted};
        (#attribute{name = b, data = 200}, state, inc, undefined) -> {update, 201, state}
    end),
    meck:expect(Mod, handle_created, fun
        (#attribute{name = c        }, set, []) -> {create, 0, state};
        (#attribute{name = undefined}, set, []) -> {create, 0, state}
    end),
    {ok, State} = eproc_fsm_attr:init([], 2, [
        #attribute{attr_id = 1, module = Mod, name = a, data = 100, scope = []},
        #attribute{attr_id = 2, module = Mod, name = b, data = 200, scope = []}
    ]),
    {ok, State} = eproc_fsm_attr:transition_start(0, 0, [some], State),
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, a, del)),             % remove attr
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, b, inc)),             % update attr
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, c, set, [])),         % create named attr
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, undefined, set, [])), % create first unnamed attr
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, undefined, set, [])), % create second unnamed attr
    {ok, Actions, _State2} = eproc_fsm_attr:transition_end(0, 0, [], State),
    ?assertEqual(5, length(Actions)),
    ?assertEqual(1, length([any || #attr_action{attr_id = 1, action = {remove, {user, deleted}}} <- Actions])),
    ?assertEqual(1, length([any || #attr_action{attr_id = 2, action = {update, [], 201}} <- Actions])),
    ?assertEqual(1, length([any || #attr_action{action = {create, c,         [], 0}} <- Actions])),
    ?assertEqual(2, length([any || #attr_action{action = {create, undefined, [], 0}} <- Actions])),
    ?assertEqual(2, meck:num_calls(Mod, handle_updated, '_')),
    ?assertEqual(3, meck:num_calls(Mod, handle_created, '_')),
    ?assert(meck:validate([Mod])),
    meck:unload([Mod]).


%%
%%  Update for unnamed attributes should fail.
%%
action_update_unnamed_test() ->
    Mod = eproc_fsm_attr__void,
    meck:new(Mod),
    meck:expect(Mod, init, fun([A, B]) -> {ok, [{A, state}, {B, state}]} end),
    {ok, State} = eproc_fsm_attr:init([], 2, [
        #attribute{attr_id = 1, module = Mod, scope = []},
        #attribute{attr_id = 2, module = Mod, scope = []}
    ]),
    {ok, State} = eproc_fsm_attr:transition_start(0, 0, [some], State),
    ?assertEqual(ok, eproc_fsm_attr:action(Mod, undefined, any)),
    ?assertError(function_clause, eproc_fsm_attr:transition_end(0, 0, [], State)),
    ?assert(meck:validate([Mod])),
    meck:unload([Mod]).


%%
%%  Check event handling.
%%
event_test() ->
    Mod = eproc_fsm_attr__void,
    meck:new(Mod),
    meck:expect(Mod, init, fun ([A]) -> {ok, [{A, state}]} end),
    meck:expect(Mod, handle_event, fun
        (#attribute{attr_id = 1}, state, my_event1) -> {handled, state1};
        (#attribute{attr_id = 1}, state, my_event2) -> {trigger, trg2, {update, data2, state2}};
        (#attribute{attr_id = 1}, state, my_event3) -> {trigger, trg3, {remove, reason3}}
    end),
    {ok, State} = eproc_fsm_attr:init([], 1, [
        #attribute{attr_id = 1, module = Mod, scope = []}
    ]),
    Event0 = any_message,
    Event1 = eproc_fsm_attr:make_event(Mod, 1, my_event1),
    Event2 = eproc_fsm_attr:make_event(Mod, 1, my_event2),
    Event3 = eproc_fsm_attr:make_event(Mod, 1, my_event3),
    ?assertEqual(unknown, eproc_fsm_attr:event(Event0, State)),
    {handled, State1}                = eproc_fsm_attr:event(Event1, State),
    {trigger, State2, trg2, Action2} = eproc_fsm_attr:event(Event2, State),
    {trigger, State3, trg3, Action3} = eproc_fsm_attr:event(Event3, State),
    ?assertEqual(#attr_action{attr_id = 1, module = Mod, action = {update, [], data2}},       Action2),
    ?assertEqual(#attr_action{attr_id = 1, module = Mod, action = {remove, {user, reason3}}}, Action3),
    ?assertEqual(3, meck:num_calls(Mod, handle_event, '_')),
    ?assert(meck:validate([Mod])),
    meck:unload([Mod]).

