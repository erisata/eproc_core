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
add_key_test() ->
    {ok, State1} = eproc_fsm_attr:init([], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [first], State1),
    ok = eproc_router:add_key(key1, next),
    ok = eproc_router:add_key(key2, []),
    {ok, [_, _], _LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [second], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [second], State3),
    {ok, [_], _LastAttrId5, _State5} = eproc_fsm_attr:transition_end(0, 0, [third], State4).


