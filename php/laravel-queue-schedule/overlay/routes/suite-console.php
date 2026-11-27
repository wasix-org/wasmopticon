<?php

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Schedule;

Schedule::call(fn () => Cache::store('database')->put('suite-scheduled', 'scheduler ran', 600))
    ->name('suite-scheduled')
    ->everyMinute();
