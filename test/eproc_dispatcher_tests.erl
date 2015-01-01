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

-module(eproc_dispatcher_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").


%%
%%  Check if dispatching works.
%%
dispatch_test() ->
    ok = meck:new(dispatch_test_mod_a, [non_strict]),
    ok = meck:new(dispatch_test_mod_b, [non_strict]),
    ok = meck:expect(dispatch_test_mod_a, handle_dispatch, fun
        (a, {x}) -> noreply;
        (b, {x}) -> {reply, bb};
        (_, {x}) -> unknown
    end),
    ok = meck:expect(dispatch_test_mod_b, handle_dispatch, fun
        (c, {y}) -> {reply, cc};
        (_, {y}) -> unknown
    end),
    {ok, D} = eproc_dispatcher:new([
        {dispatch_test_mod_a, {x}},
        {dispatch_test_mod_b, {y}}
    ]),
    ?assertThat(eproc_dispatcher:dispatch(D, a), is(noreply)),
    ?assertThat(eproc_dispatcher:dispatch(D, b), is({reply, bb})),
    ?assertThat(eproc_dispatcher:dispatch(D, c), is({reply, cc})),
    ?assertThat(eproc_dispatcher:dispatch(D, d), is({error, unknown})),
    ?assert(meck:validate([dispatch_test_mod_a, dispatch_test_mod_b])),
    ok = meck:unload([dispatch_test_mod_a, dispatch_test_mod_b]).


