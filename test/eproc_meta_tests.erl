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

-module(eproc_meta_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Check if init works.
%%
init_test() ->
    Attr = #attribute{
        inst_id = iid, module = eproc_meta, name = {tag, a, b},
        scope = [], data = {data, a, b}, from = from_trn
    },
    {ok, _State} = eproc_fsm_attr:init([], 0, [Attr]).


%%
%%  Check if attribute creation and updating works.
%%
add_tag_test() ->
    {ok, State1} = eproc_fsm_attr:init([], 0, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [], State1),
    ok = eproc_meta:add_tag(tag1, type),
    ok = eproc_meta:add_tag(tag2, type),
    {ok, [_, _], LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [], State3),
    ok = eproc_meta:add_tag(tag1, type),
    ?assertMatch({ok, [], LastAttrId3, State4}, eproc_fsm_attr:transition_end(0, 0, [], State4)).


