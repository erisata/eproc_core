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
%%
%%
set_test() ->
    ok = meck:new(eproc_fsm),
    ok = meck:expect(eproc_fsm, register_message, fun(_Sender, msg) -> ok end),
    ok = meck:expect(eproc_fsm, register_attr_action, fun(eproc_timer, undefined, {timer, 1000, msg}, next) -> ok end),
    ok = eproc_timer:set(1000, msg),
    ?assert(meck:validate(eproc_fsm)),
    ok = meck:unload(eproc_fsm).


%%
%%
%%
started_test() ->
    Attr = #attribute{
        inst_id = iid, module = eproc_timer, name = undefined, scope = [],
        from = from_trn, upds = [], till = undefined, reason = undefined
    },
    {ok, [{Attr, {timer, Ref}}]} = eproc_fsm_attr:init(0, [Attr]).


