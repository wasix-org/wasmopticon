<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::prefix('suite/users')->withoutMiddleware('web')->group(function () {
    Route::post('/', function (Request $request) {
        $data = $request->validate(['name' => 'required|string|max:80', 'email' => 'required|email']);
        DB::table('users')->insert($data + ['password' => 'fixture-only']);

        return response()->json($data, 201);
    });

    Route::get('/{email}', function (string $email) {
        $user = DB::table('users')->where('email', $email)->first(['name', 'email']);
        abort_if($user === null, 404);

        return response()->json($user);
    });

    Route::post('/rollback', function (Request $request) {
        $data = $request->validate(['name' => 'required|string|max:80', 'email' => 'required|email']);
        $rollback = new RuntimeException('fixture rollback');
        try {
            DB::transaction(function () use ($data, $rollback) {
                DB::table('users')->insert($data + ['password' => 'fixture-only']);
                abort_unless(DB::table('users')->where('email', $data['email'])->exists(), 500);
                throw $rollback;
            });
        } catch (RuntimeException $exception) {
            if ($exception !== $rollback) {
                throw $exception;
            }
        }

        return response()->json(['rolled_back' => true]);
    });
});
