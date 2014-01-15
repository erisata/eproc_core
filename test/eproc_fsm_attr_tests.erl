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
    meck:expect(eproc_fsm_attr_test1, init, fun([A, B]) -> {ok, [{A, undefined}, {B, undefined}]} end),
    meck:expect(eproc_fsm_attr_test2, init, fun([C]) -> {ok, [{C, undefined}]} end),
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
    meck:expect(eproc_fsm_attr_test1, init, fun([A]) -> {ok, [{A, undefined}]} end),
    {ok, State} = eproc_fsm_attr:init([], 0, [#attribute{module = eproc_fsm_attr_test1, scope = []}]),
    ?assertMatch({ok, State}, eproc_fsm_attr:transition_start([], State)),
    ?assertEqual([], erlang:get('eproc_fsm_attr$actions')),
    true = meck:validate([eproc_fsm_attr_test1]),
    meck:unload([eproc_fsm_attr_test1]).

%%
%%  Test if transition is completed properly.
%%
transition_end_empty_test() ->
    meck:new(eproc_fsm_attr_test1, [non_strict]),
    meck:expect(eproc_fsm_attr_test1, init, fun([A]) -> {ok, [{A, undefined}]} end),
    {ok, State} = eproc_fsm_attr:init([], 0, [#attribute{module = eproc_fsm_attr_test1, scope = []}]),
    {ok, State} = eproc_fsm_attr:transition_start([], State),
    {ok, State} = eproc_fsm_attr:transition_end([], [], State),
    ?assertEqual(undefined, erlang:get('eproc_fsm_attr$actions')),
    true = meck:validate([eproc_fsm_attr_test1]),
    meck:unload([eproc_fsm_attr_test1]).


%%
%%  Test if clenup by scope works.
%%
transition_end_remove_test() ->
    meck:new(eproc_fsm_attr__void),
    meck:expect(eproc_fsm_attr__void, init, fun([A, B]) -> {ok, [{A, undefined}, {B, undefined}]} end),
    meck:expect(eproc_fsm_attr__void, removed, fun(Attr) -> {ok, something} end),
    {ok, State} = eproc_fsm_attr:init([], 0, [
        #attribute{module = eproc_fsm_attr__void, scope = []},
        #attribute{module = eproc_fsm_attr__void, scope = [some]}
    ]),
    {ok, State} = eproc_fsm_attr:transition_start([some], State),
    {ok, State} = eproc_fsm_attr:transition_end([], [some], State),
    ?assert(meck:called(eproc_fsm_attr__void, removed, '_')),  % TODO
    ?assert(meck:validate([eproc_fsm_attr__void])),
    meck:unload([eproc_fsm_attr__void]).


%%
%%  Test if attribute is added, updated and removed.
%%
action_test() ->
    ?assert(not_implemented). % TODO


