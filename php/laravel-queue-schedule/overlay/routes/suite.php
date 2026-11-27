<?php

use App\Jobs\RecordFixture;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::withoutMiddleware('web')->group(function () {
    Route::post('/suite/dispatch', function (Request $request) {
        $data = $request->validate(['value' => 'required|string|max:80']);
        Bus::dispatch(new RecordFixture($data['value']));

        return response()->json(['queued' => true], 202);
    });

    Route::get('/suite/results', fn () => response()->json([
        'pending' => DB::table('jobs')->count(),
        'handled' => Cache::store('database')->get('suite-queued'),
        'scheduled' => Cache::store('database')->get('suite-scheduled'),
    ]));
});
