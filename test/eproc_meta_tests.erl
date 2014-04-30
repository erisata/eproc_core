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
-include_lib("hamcrest/include/hamcrest.hrl").


%%
%%  Check if init works.
%%
init_test() ->
    Attr = #attribute{
        inst_id = iid, module = eproc_meta, name = {tag, a, b},
        scope = [], data = {data, a, b}, from = from_trn
    },
    {ok, _State} = eproc_fsm_attr:init([], 0, store, [Attr]).


%%
%%  Check if attribute creation and updating works.
%%
add_tag_test() ->
    {ok, State1} = eproc_fsm_attr:init([], 0, store, []),
    {ok, State2} = eproc_fsm_attr:transition_start(0, 0, [], State1),
    ok = eproc_meta:add_tag(tag1, type),
    ok = eproc_meta:add_tag(tag2, type),
    {ok, [_, _], LastAttrId3, State3} = eproc_fsm_attr:transition_end(0, 0, [], State2),
    {ok, State4} = eproc_fsm_attr:transition_start(0, 0, [], State3),
    ok = eproc_meta:add_tag(tag1, type),
    {ok, [], LastAttrId3, State5} = eproc_fsm_attr:transition_end(0, 0, [], State4),
    {state, _, Attrs4, store} = State4,
    {state, _, Attrs5, store} = State5,
    ?assertEqual(lists:sort(Attrs4), lists:sort(Attrs5)).


%%
%%  Check, if `get_instances/1` works.
%%
get_instances_test() ->
    ok = meck:new(eproc_store, []),
    ok = meck:expect(eproc_store, attr_task, fun
        (store, eproc_meta, {get_instances, {tags, [{tag1, type1}]}}) -> ok
    end),
    ?assertThat(eproc_meta:get_instances({tags, [{tag1, type1}]}, [{store, store}]), is(ok)),
    ?assert(meck:validate([eproc_store])),
    ok = meck:unload([eproc_store]).


