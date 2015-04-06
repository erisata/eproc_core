

# Module eproc_dispatcher #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_dispatcher` behaviour.__
<br></br>
 Required callback functions: `handle_dispatch/2`.

<a name="types"></a>

## Data Types ##




### <a name="type-dispatcher_spec">dispatcher_spec()</a> ###



<pre><code>
dispatcher_spec() = {Module::module(), Args::list()}
</code></pre>


<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#dispatch-2">dispatch/2</a></td><td></td></tr><tr><td valign="top"><a href="#new-1">new/1</a></td><td></td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="dispatch-2"></a>

### dispatch/2 ###


<pre><code>
dispatch(Dispatcher::term(), Event::term()) -&gt; noreply | {reply, Reply::term()} | {error, unknown}
</code></pre>

<br></br>



<a name="new-1"></a>

### new/1 ###


<pre><code>
new(DispatcherSpecs::[<a href="#type-dispatcher_spec">dispatcher_spec()</a>]) -&gt; {ok, Dispatcher::term()}
</code></pre>

<br></br>



<a name="new-2"></a>

### new/2 ###


<pre><code>
new(DispatcherSpecs::[<a href="#type-dispatcher_spec">dispatcher_spec()</a>], Opts::[]) -&gt; {ok, Dispatcher::term()}
</code></pre>

<br></br>



