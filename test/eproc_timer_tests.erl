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

-module(eproc_timer_tests).
-compile([{parse_transform, lager_transform}]).
-include("eproc.hrl").
-include_lib("eunit/include/eunit.hrl").

%%
%%  Check if attribute action specs are registered correctly for the `set` functions.
%%
set_plain_test() ->
    ok = meck:new(eproc_fsm),
    ok = meck:new(eproc_fsm_attr),
    ok = meck:expect(eproc_fsm, register_message, fun
        ({timer, undefined}, msg1) -> ok;
        ({timer, undefined}, msg2) -> ok;
        ({timer, some},      msg3) -> ok
    end),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, undefined, {timer, 1000, msg1}, next) -> ok;
        (eproc_timer, undefined, {timer, 1000, msg2}, []) -> ok;
        (eproc_timer, some,      {timer, 1000, msg3}, []) -> ok
    end),
    ok = eproc_timer:set(1000, msg1),
    ok = eproc_timer:set(1000, msg2, []),
    ok = eproc_timer:set(some, 1000, msg3, []),
    ?assertEqual(3, meck:num_calls(eproc_fsm, register_message, '_')),
    ?assertEqual(3, meck:num_calls(eproc_fsm_attr, action, '_')),
    ?assert(meck:validate([eproc_fsm, eproc_fsm_attr])),
    ok = meck:unload([eproc_fsm, eproc_fsm_attr]).


%%
%%  Check if attribute actuib spec is registered correctly for the `cancel` function.
%%
cancel_plain_test() ->
    ok = meck:new(eproc_fsm_attr),
    ok = meck:expect(eproc_fsm_attr, action, fun
        (eproc_timer, aaa, {timer, remove}) -> ok
    end),
    ok = eproc_timer:cancel(aaa),
    ?assertEqual(1, meck:num_calls(eproc_fsm_attr, action, '_')),
    ?assert(meck:validate(eproc_fsm_attr)),
    ok = meck:unload(eproc_fsm_attr).


%%
%%  Check if existing timers are restarted on init.
%%
init_restart_test() ->
    OldNow = erlang:now(),
    receive after 200 -> ok end,
    Attr1 = #attribute{ % In the past.
        inst_id = iid, module = eproc_timer, name = undefined, scope = [],
        data = {data, OldNow, 100, msg1},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    Attr2 =  #attribute{ % In the future.
        inst_id = iid, module = eproc_timer, name = undefined, scope = [],
        data = {data, erlang:now(), 100, msg2},
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    {ok, State} = eproc_fsm_attr:init([], 0, [Attr1, Attr2]),
    ?assert(receive TimerMsg -> true after 200 -> false end),
    ?assert(receive TimerMsg -> true after 400 -> false end).


%%
%%  TODO: Add the folowing tests:
%%    * set/create with attr impl including firing.
%%    * set/update with attr impl including firing.
%%    * cancel of existing timer.
%%    * remove by scope.
%%    * handle_event
%%


