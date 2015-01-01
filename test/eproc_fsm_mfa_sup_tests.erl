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

-module(eproc_fsm_mfa_sup_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%
%%  Check if supervisor can be started and child FSM created.
%%
start_fsm_test() ->
    TestPid = self(),
    ok = meck:new(some_fsm, [non_strict]),
    ok = meck:expect(some_fsm, some_function, fun
        ({inst, 425}, [some], other_args, '$fsm_ref') ->
            {ok, TestPid}
    end),
    {ok, Sup} = eproc_fsm_mfa_sup:start_link({local, eproc_fsm_mfa_sup_tests}),
    {ok, Fsm} = eproc_fsm_mfa_sup:start_fsm(
        eproc_fsm_mfa_sup_tests, {inst, 425},
        {some_fsm, some_function, [{inst, 425}, [some], other_args, '$fsm_ref']}
    ),
    ?assertEqual(Fsm, TestPid),
    ?assertEqual(1, meck:num_calls(some_fsm, some_function, '_')),
    ?assert(unlink(Sup)),    %% Supervisor <-> FSM.
    ?assert(unlink(Sup)),    %% Supervisor <-> Test.
    exit(Sup, kill),
    ?assert(meck:validate([some_fsm])),
    ok = meck:unload([some_fsm]).


