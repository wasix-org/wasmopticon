<?php

namespace App\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Support\Facades\Cache;

final class RecordFixture implements ShouldQueue
{
    public function __construct(public string $value)
    {
    }

    public function handle(): void
    {
        Cache::store('database')->put('suite-queued', $this->value, 600);
    }
}
