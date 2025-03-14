<?php

/**
 * Fetches the body of a website using cURL and returns
 * status code, duration, and response size.
 *
 * @param string $url The website to fetch
 * @return array Associative array containing:
 *               - status_code (int)
 *               - duration (float)
 *               - response_size (int)
 */
function fetch_website($url)
{
    // Write log GET <url> to stderr
    error_log("GET $url", 0);

    $ch = curl_init($url);

    // Return the transfer as a string
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

    $start = microtime(true);
    $response = curl_exec($ch);
    $statusCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $end = microtime(true);

    curl_close($ch);

    $duration = $end - $start;
    $responseSize = strlen($response);

    return [
        'status_code'   => $statusCode,
        'duration'      => $duration,
        'response_size' => $responseSize
    ];
}

/**
 * Runs fetch_website() multiple times and collects metrics
 *
 * @param string $url The website to fetch
 * @param int    $count Number of times to fetch
 * @return array JSON-serializable array with detailed results and aggregates
 */
function benchmark_website($url, $count)
{
    $results    = [];
    $durations  = [];
    $sizes      = [];

    for ($i = 0; $i < $count; $i++) {
        $res = fetch_website($url);
        $results[]   = $res;
        $durations[] = $res['duration'];
        $sizes[]     = $res['response_size'];
    }

    // Calculate aggregates
    $aggregate = [
        'avg_duration' => array_sum($durations) / $count,
        'min_duration' => min($durations),
        'max_duration' => max($durations),
        'avg_size'     => array_sum($sizes) / $count,
        'min_size'     => min($sizes),
        'max_size'     => max($sizes),
	'total_duration' => array_sum($durations),
	'total_size' => array_sum($sizes)
    ];

    // Optionally, you can check if all attempts had the same status code,
    // or just use the last or first. Below we store just the first fetch's code:
    $aggregate['status_code'] = $results[0]['status_code'];

    return [
        'results'   => $results,
        'aggregate' => $aggregate
    ];
}

/**
 * Reads GET parameters (?url=...&count=...) and prints benchmark results as JSON.
 */
// function run_benchmark()
// {
//     // Read parameters (defaults if missing)
//     $url = isset($_GET['url']) ? $_GET['url'] : null;
//     $count = isset($_GET['count']) ? (int)$_GET['count'] : 1;
//
//     // If the URL is missing, return an error message
//     if (!$url) {
//         header('Content-Type: application/json');
//         echo json_encode(['error' => 'Missing required parameter: url']);
//         exit;
//     }
//
//     // Perform the benchmark
//     $benchmarkResults = benchmark_website($url, $count);
//
//     // Output as JSON
//     header('Content-Type: application/json');
//     echo json_encode($benchmarkResults);
// }
