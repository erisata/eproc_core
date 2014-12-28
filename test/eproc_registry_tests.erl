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

-module(eproc_registry_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Check if eproc_registry:ref/0 works with existing configuration.
%%
reg_from_env_test() ->
    ok = meck:new(eproc_core_app, []),
    ok = meck:expect(eproc_core_app, registry_cfg, fun
        () -> {ok, {eproc_reg_gproc, ref, []}}
    end),
    ?assertEqual({ok, {eproc_reg_gproc, []}}, eproc_registry:ref()),
    ?assert(meck:validate(eproc_core_app)),
    ok = meck:unload(eproc_core_app).


%%
%%  Check if eproc_registry:ref/0 works with missing configuration.
%%
reg_undefined_test() ->
    ok = meck:new(eproc_core_app, []),
    ok = meck:expect(eproc_core_app, registry_cfg, fun
        () -> undefined
    end),
    ?assertEqual(undefined, eproc_registry:ref()),
    ?assert(meck:validate(eproc_core_app)),
    ok = meck:unload(eproc_core_app).


%%
%%  Check if eproc_registry:ref/2 works.
%%
reg_explicit_test() ->
    ?assertEqual({ok, {mod, args}}, eproc_registry:ref(mod, args)).


%%
%%  Check if eproc_registry:supervisor_child_specs/1 works.
%%
supervisor_child_specs_test() ->
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:expect(eproc_reg_gproc, supervisor_child_specs, fun
        ([]) -> {ok, [some, specs]}
    end),
    ?assertEqual({ok, [some, specs]}, eproc_registry:supervisor_child_specs(Registry)),
    ?assert(meck:validate(eproc_reg_gproc)),
    ok = meck:unload(eproc_reg_gproc).


%%
%%  Check if eproc_registry:make_new_fsm_ref/3 works.
%%
make_new_fsm_ref_test() ->
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, []),
    ?assertEqual(
        {ok, {via, eproc_reg_gproc, {new, [], {inst, 1}, {default, []}}}},
        eproc_registry:make_new_fsm_ref(Registry, {inst, 1}, {default, []})
    ).


%%
%%  Check if eproc_registry:make_fsm_ref/3 works.
%%
make_fsm_ref_test() ->
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, []),
    ?assertEqual(
        {ok, {via, eproc_reg_gproc, {fsm, [], {inst, 1}}}},
        eproc_registry:make_fsm_ref(Registry, {inst, 1})
    ).


%%
%%  Check if eproc_registry:register_fsm/3 works.
%%
register_fsm_test() ->
    {ok, Registry} = eproc_registry:ref(eproc_reg_gproc, []),
    ok = meck:new(eproc_reg_gproc, []),
    ok = meck:expect(eproc_reg_gproc, register_fsm, fun
        ([], {inst, 123}, [{inst, 123}, {name, n1}]) -> ok
    end),
    ?assertEqual(ok, eproc_registry:register_fsm(Registry, {inst, 123}, [{inst, 123}, {name, n1}])),
    ?assert(meck:validate(eproc_reg_gproc)),
    ok = meck:unload(eproc_reg_gproc).


