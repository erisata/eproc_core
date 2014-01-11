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
%%
%%
init_empty_test() ->
    {ok, _State} = eproc_fsm_attr:init([], 0, []).


init_mock_test() ->
    meck:new(eproc_fsm_attr_test1, [non_strict]),
    meck:new(eproc_fsm_attr_test2, [non_strict]),
    meck:expect(eproc_fsm_attr_test1, init, fun([A, B]) -> {ok, [{A, undefined}, {B, undefined}]} end),
    meck:expect(eproc_fsm_attr_test2, init, fun([C]) -> {ok, [{C, undefined}]} end),
    {ok, _State} = eproc_fsm_attr:init([], 0, [
        #attribute{module = eproc_fsm_attr_test1},
        #attribute{module = eproc_fsm_attr_test1},
        #attribute{module = eproc_fsm_attr_test2}
    ]),
    meck:validate([eproc_fsm_attr_test1, eproc_fsm_attr_test2]),
    meck:unload([eproc_fsm_attr_test1, eproc_fsm_attr_test2]).



