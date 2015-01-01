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
-module(eproc_store_tests).
-compile([{parse_transform, lager_transform}]).
-include("include/eproc.hrl").
-include_lib("eunit/include/eunit.hrl").

%%
%%  Check, if `apply_transition/3` works.
%%
apply_transition_test() ->
    ok = meck:new(eproc_fsm_attr, []),
    ok = meck:expect(eproc_fsm_attr, apply_actions, fun
        (attr_acts1, attrs0, iid, 1) -> {ok, attrs1};
        (attr_acts2, attrs1, iid, 2) -> {ok, attrs2}
    end),
    State0 = #inst_state{
        stt_id = 0,
        attrs_active = attrs0
    },
    Trn1 = #transition{
        trn_id = 1,
        sname = [sn1],
        sdata = sd1,
        timestamp = {0, 0, 1},
        attr_last_nr = 101,
        attr_actions = attr_acts1
    },
    Trn2 = #transition{
        trn_id = 2,
        sname = [sn2],
        sdata = sd2,
        timestamp = {0, 0, 2},
        attr_last_nr = 102,
        attr_actions = attr_acts2
    },
    State1 = eproc_store:apply_transition(Trn1, State0, iid),
    State2 = eproc_store:apply_transition(Trn2, State1, iid),
    #inst_state{
        stt_id = 2,
        sname = [sn2],
        sdata = sd2,
        timestamp = {0, 0, 2},
        attr_last_nr = 102,
        attrs_active = attrs2
    } = State2,
    ?assertEqual(2, meck:num_calls(eproc_fsm_attr, apply_actions, '_')),
    ?assert(meck:validate(eproc_fsm_attr)),
    ok = meck:unload(eproc_fsm_attr).


%%
%%  TODO: Check if `is_instance_terminated/1` works.
%%  TODO: Check if `make_resume_attempt/3` works.
%%  TODO: Check if `determine_transition_action/2` works.
%%


