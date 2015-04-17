

# Module eproc_limits #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md).

<a name="types"></a>

## Data Types ##




### <a name="type-const_delay">const_delay()</a> ###



<pre><code>
const_delay() = {delay, Delay::<a href="#type-duration">duration()</a>}
</code></pre>





### <a name="type-exp_delay">exp_delay()</a> ###



<pre><code>
exp_delay() = {delay, MinDelay::<a href="#type-duration">duration()</a>, Coefficient::number(), MaxDelay::<a href="#type-duration">duration()</a>}
</code></pre>





### <a name="type-limit_action">limit_action()</a> ###



<pre><code>
limit_action() = notify | <a href="#type-exp_delay">exp_delay()</a> | <a href="#type-const_delay">const_delay()</a>
</code></pre>





### <a name="type-limit_spec">limit_spec()</a> ###



<pre><code>
limit_spec() = <a href="#type-series_spec">series_spec()</a> | <a href="#type-rate_spec">rate_spec()</a>
</code></pre>





### <a name="type-rate_spec">rate_spec()</a> ###



<pre><code>
rate_spec() = {rate, LimitName::term(), MaxCount::integer(), Duration::<a href="#type-duration">duration()</a>, Action::<a href="#type-limit_action">limit_action()</a>}
</code></pre>





### <a name="type-series_spec">series_spec()</a> ###



<pre><code>
series_spec() = {series, LimitName::term(), MaxCount::integer(), NewAfter::<a href="#type-duration">duration()</a>, Action::<a href="#type-limit_action">limit_action()</a>}
</code></pre>


<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#cleanup-1">cleanup/1</a></td><td></td></tr><tr><td valign="top"><a href="#cleanup-2">cleanup/2</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#notify-2">notify/2</a></td><td></td></tr><tr><td valign="top"><a href="#notify-3">notify/3</a></td><td></td></tr><tr><td valign="top"><a href="#reset-1">reset/1</a></td><td></td></tr><tr><td valign="top"><a href="#reset-2">reset/2</a></td><td></td></tr><tr><td valign="top"><a href="#setup-3">setup/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="cleanup-1"></a>

### cleanup/1 ###


<pre><code>
cleanup(ProcessName::term()) -&gt; ok
</code></pre>

<br></br>



<a name="cleanup-2"></a>

### cleanup/2 ###


<pre><code>
cleanup(ProcessName::term(), CounterName::term()) -&gt; ok
</code></pre>

<br></br>



<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`


<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(Event, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(Event, State) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Event, State) -> any()`


<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="notify-2"></a>

### notify/2 ###


<pre><code>
notify(ProcessName::term(), Counters::[{CounterName::term(), Count::integer()}]) -&gt; ok | {reached, [{CounterName::term(), [LimitName::term()]}]} | {delay, DelayMS::integer()} | {error, {not_found, CounterName::term()}}
</code></pre>

<br></br>



<a name="notify-3"></a>

### notify/3 ###


<pre><code>
notify(ProcessName::term(), CounterName::term(), Count::integer()) -&gt; ok | {reached, [LimitName::term()]} | {delay, DelayMS::integer()} | {error, {not_found, CounterName::term()}}
</code></pre>

<br></br>



<a name="reset-1"></a>

### reset/1 ###


<pre><code>
reset(ProcessName::term()) -&gt; ok
</code></pre>

<br></br>



<a name="reset-2"></a>

### reset/2 ###


<pre><code>
reset(ProcessName::term(), CounterName::term()) -&gt; ok
</code></pre>

<br></br>



<a name="setup-3"></a>

### setup/3 ###


<pre><code>
setup(ProcessName::term(), CounterName::term(), Spec::undefined | <a href="#type-limit_spec">limit_spec()</a> | [<a href="#type-limit_spec">limit_spec()</a>]) -&gt; ok
</code></pre>

<br></br>



<a name="start_link-0"></a>

### start_link/0 ###

`start_link() -> any()`


<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`


