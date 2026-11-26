<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/suite/form', function (Request $request) {
    return view('suite', [
        'email' => $request->session()->get('suite_email'),
    ]);
});

Route::post('/suite/form', function (Request $request) {
    $data = $request->validate(['name' => 'required|string|max:80']);
    $database = config('database.connections.sqlite.database');
    if (! is_file($database)) {
        touch($database);
        abort_unless(Artisan::call('migrate', ['--force' => true]) === 0, 500);
    }

    $email = bin2hex(random_bytes(8)).'@suite.example';
    DB::table('users')->insert([
        'name' => $data['name'],
        'email' => $email,
        'password' => 'fixture-only',
    ]);
    $request->session()->put('suite_email', $email);

    return redirect('/suite/form');
});

Route::get('/suite/entry', function (Request $request) {
    $email = $request->session()->get('suite_email');
    abort_if($email === null, 404);
    $entry = DB::table('users')->where('email', $email)->first(['name', 'email']);
    abort_if($entry === null, 404);

    return response()->json($entry);
});
