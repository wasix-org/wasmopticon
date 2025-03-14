<?php

// Adopted from https://github.com/sergix44/php-benchmark-script
// https://github.com/sergix44/php-benchmark-script/blob/07aae0baabafcaa46b1c3ec04bcca962aa6f309f/bench.php
//
// Only change is to move everyting into a class, and to not print text output
// but instead return results as an array.
class PhpBench
{
    /**
     * Default arguments
     */
    private static $defaultArgs = [
        'multiplier' => 1.0,
    ];

    /**
     * Registered setup hooks
     *
     * @var callable[]
     */
    private static $setupHooks = [];

    /**
     * Registered teardown hooks
     *
     * @var callable[]
     */
    private static $cleanupHooks = [];

    /**
     * Extra stats lines
     *
     * @var array<array{0:string,1:mixed}>
     */
    private static $extraLines = [];

    /**
     * Name of the benchmark currently running (used only if you want to log or store extra stats).
     *
     * @var string|null
     */
    private static $currentBenchmark = null;

    /**
     * Tracks total time across all benchmarks.
     * If you want to reset between runs, you can zero it in bench() before usage.
     *
     * @var float
     */
    private static $totalTime = 0.0;

    /**
     * Current stopwatch start time
     *
     * @var float
     */
    private static $startTime = 0.0;

    /**
     * The built-in benchmarks.
     *
     * @var array<string,callable>
     */
    private static function benchmarks() {
	    return [
        'math' => function ($multiplier = 1, $count = 200000) {
            $x = 0;
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                $x += $i + $i;
                $x += $i * $i;
                $x += $i ** $i;
                $x += $i / (($i + 1) * 2);
                $x += $i % (($i + 1) * 2);
                abs($i);
                acos($i);
                acosh($i);
                asin($i);
                asinh($i);
                atan2($i, $i);
                atan($i);
                atanh($i);
                ceil($i);
                cos($i);
                cosh($i);
                decbin($i);
                dechex($i);
                decoct($i);
                deg2rad($i);
                exp($i);
                expm1($i);
                floor($i);
                fmod($i, $i);
                hypot($i, $i);
                is_infinite($i);
                is_finite($i);
                is_nan($i);
                log10($i);
                log1p($i);
                log($i);
                pi();
                pow($i, $i);
                rad2deg($i);
                sin($i);
                sinh($i);
                sqrt($i);
                tan($i);
                tanh($i);
            }
            return $i;
        },
        'loops' => function ($multiplier = 1, $count = 20000000) {
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; ++$i) {
                $i;
            }
            $i = 0;
            while ($i < $count) {
                ++$i;
            }
            return $i;
        },
        'ifelse' => function ($multiplier = 1, $count = 10000000) {
            $a = 0;
            $b = 0;
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                $k = $i % 4;
                if ($k === 0) {
                    $i;
                } elseif ($k === 1) {
                    $a = $i;
                } elseif ($k === 2) {
                    $b = $i;
                } else {
                    $i;
                }
            }
            return $a - $b;
        },
        'switch' => function ($multiplier = 1, $count = 10000000) {
            $a = 0;
            $b = 0;
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                switch ($i % 4) {
                    case 0:
                        $i;
                        break;
                    case 1:
                        $a = $i;
                        break;
                    case 2:
                        $b = $i;
                        break;
                    default:
                        break;
                }
            }
            return $a - $b;
        },
        'string' => function ($multiplier = 1, $count = 50000) {
            $string = '<i>the</i> quick brown fox jumps over the lazy dog  ';
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                addslashes($string);
                bin2hex($string);
                chunk_split($string);
                convert_uudecode(convert_uuencode($string));
                count_chars($string);
                explode(' ', $string);
                htmlentities($string);
                md5($string);
                metaphone($string);
                ord($string);
                rtrim($string);
                sha1($string);
                soundex($string);
                str_getcsv($string);
                str_ireplace('fox', 'cat', $string);
                str_pad($string, 50);
                str_repeat($string, 10);
                str_replace('fox', 'cat', $string);
                str_rot13($string);
                str_shuffle($string);
                str_word_count($string);
                strip_tags($string);
                strpos($string, 'fox');
                strlen($string);
                strtolower($string);
                strtoupper($string);
                substr_count($string, 'the');
                trim($string);
                ucfirst($string);
                ucwords($string);
            }
            return $string;
        },
        'array' => function ($multiplier = 1, $count = 50000) {
            $a = range(0, 100);
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                array_keys($a);
                array_values($a);
                array_flip($a);
                array_map(function ($e) {
                }, $a);
                array_walk($a, function ($e, $i) {
                });
                array_reverse($a);
                array_sum($a);
                array_merge($a, [101, 102, 103]);
                array_replace($a, [1, 2, 3]);
                array_chunk($a, 2);
            }
            return $a;
        },
        'regex' => function ($multiplier = 1, $count = 1000000) {
            for ($i = 0; $i < $count * $multiplier; $i++) {
                preg_match("#http[s]?://\w+[^\s\[\]\<]+#",
                    'this is a link to https://google.com which is a really popular site');
                preg_replace("#(^|\s)(http[s]?://\w+[^\s\[\]\<]+)#i", '\1<a href="\2">\2</a>',
                    'this is a link to https://google.com which is a really popular site');
            }
            return $i;
        },
        'is_{type}' => function ($multiplier = 1, $count = 2500000) {
            $o = new \stdClass();
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                is_array([1]);
                is_array('1');
                is_int(1);
                is_int('abc');
                is_string('foo');
                is_string(123);
                is_bool(true);
                is_bool(5);
                is_numeric('hi');
                is_numeric('123');
                is_float(1.3);
                is_float(0);
                is_object($o);
                is_object('hi');
            }
            return $o;
        },
        'hash' => function ($multiplier = 1, $count = 10000) {
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                md5($i);
                sha1($i);
                hash('sha256', $i);
                hash('sha512', $i);
                hash('ripemd160', $i);
                hash('crc32', $i);
                hash('crc32b', $i);
                hash('adler32', $i);
                hash('fnv132', $i);
                hash('fnv164', $i);
                hash('joaat', $i);
                hash('haval128,3', $i);
                hash('haval160,3', $i);
                hash('haval192,3', $i);
                hash('haval224,3', $i);
                hash('haval256,3', $i);
                hash('haval128,4', $i);
                hash('haval160,4', $i);
                hash('haval192,4', $i);
                hash('haval224,4', $i);
                hash('haval256,4', $i);
                hash('haval128,5', $i);
                hash('haval160,5', $i);
                hash('haval192,5', $i);
                hash('haval224,5', $i);
                hash('haval256,5', $i);
            }
            return $i;
        },
        'json' => function ($multiplier = 1, $count = 100000) {
            $data = [
                'foo' => 'bar',
                'bar' => 'baz',
                'baz' => 'qux',
                'qux' => 'quux',
                'quux' => 'corge',
                'corge' => 'grault',
                'grault' => 'garply',
                'garply' => 'waldo',
                'waldo' => 'fred',
                'fred' => 'plugh',
                'plugh' => 'xyzzy',
                'xyzzy' => 'thud',
                'thud' => 'end',
            ];
            $count = $count * $multiplier;
            for ($i = 0; $i < $count; $i++) {
                json_encode($data);
                json_decode(json_encode($data));
            }
            return $data;
        },
      ];
    }

    /**
     * Entry point to run the entire benchmark.
     * It returns an array with environment info, each benchmark time, total time, etc.
     *
     * @return array<string,mixed>
     */
    public static function bench()
    {
        // Throw if PHP < 5.6
        if (PHP_MAJOR_VERSION < 5 || (PHP_MAJOR_VERSION === 5 && PHP_MINOR_VERSION < 6)) {
            throw new \RuntimeException('This script requires PHP 5.6 or higher.');
        }

        // Reset total time on each run if desired
        self::$totalTime = 0.0;
        self::$extraLines = [];

        // Parse arguments (CLI or Query string)
        $args = array_merge(self::$defaultArgs, self::getArgs(self::$defaultArgs));
        $multiplier = $args['multiplier'];

        // Load any external or additional benchmarks
        $additionalBenchmarks = self::loadAdditionalBenchmarks();
        $benchmarks = array_merge(self::benchmarks(), $additionalBenchmarks);

        // Run setup hooks
        foreach (self::$setupHooks as $hook) {
            $hook($args);
        }

        // Collect some environment info
        $results = [];
        $results['info'] = [
            'version'            => '2.0',
            'php_version'        => PHP_VERSION,
            'platform'           => PHP_OS,
            'arch'               => php_uname('m'),
            'opcache_enabled'    => (function_exists('opcache_get_status') && is_array(opcache_get_status()) && @opcache_get_status()['opcache_enabled']) ? 'enabled' : 'disabled',
            'opcache_jit'        => (function_exists('opcache_get_status') && is_array(opcache_get_status()) && @opcache_get_status()['jit']['enabled']) ? 'enabled' : 'disabled/unavailable',
            'pcre_jit'           => ini_get('pcre.jit') ? 'enabled' : 'disabled',
            'xdebug'             => extension_loaded('xdebug') ? 'enabled' : 'disabled',
            'memory_limit'       => ini_get('memory_limit'),
            'multiplier'         => "{$multiplier}x",
            'started_at'         => (new \DateTime())->format('d/m/Y H:i:s.v'),
        ];

        // Run each benchmark and store timings
        $results['benchmarks'] = [];
        foreach ($benchmarks as $name => $benchmark) {
            self::$currentBenchmark = $name;
            $res = self::runBenchmark($benchmark, $multiplier);
            $results['benchmarks'][$name] = $res;
        }

        // If extra lines/stats were recorded, collect them
        if (!empty(self::$extraLines)) {
            $results['extra'] = [];
            foreach (self::$extraLines as $line) {
                // $line[0] = 'currentBenchmark::someStat', $line[1] = value
                $results['extra'][] = [
                    'name'  => $line[0],
                    'value' => $line[1],
                ];
            }
        }

        // Run teardown hooks
        foreach (self::$cleanupHooks as $hook) {
            $hook($args);
        }

        // Final stats
        $results['totals'] = [
            'total_time_s'       => self::$totalTime,
            'peak_memory_usage'  => round(memory_get_peak_usage(true) / 1024 / 1024, 2) . ' MiB',
        ];

        return $results;
    }

    /**
     * Load additional benchmarks (if any).
     *
     * @return array<string, callable>
     */
    private static function loadAdditionalBenchmarks()
    {
        $benchmarks = [];
        // Adjust this path if needed
        $benchFiles = glob(__DIR__ . '/*.bench.php');
        if (!$benchFiles) {
            return $benchmarks;
        }

        foreach ($benchFiles as $benchFile) {
            $benchName = basename($benchFile, '.bench.php');
            $newBenchmark = require $benchFile;
            if (is_callable($newBenchmark)) {
                $benchmarks[$benchName] = $newBenchmark;
                continue;
            }
            if (is_array($newBenchmark)) {
                // each element of the returned array must be a callable
                $newBenchmark = array_filter($newBenchmark, 'is_callable');
                // rename them to benchFileName::functionName
                $newBenchmark = array_combine(
                    array_map(
                        function ($name) use ($benchName) {
                            return "{$benchName}::{$name}";
                        },
                        array_keys($newBenchmark)
                    ),
                    $newBenchmark
                );
                $benchmarks = array_merge($benchmarks, $newBenchmark);
                continue;
            }
            throw new \RuntimeException("Invalid benchmark file: {$benchFile}");
        }
        return $benchmarks;
    }

    /**
     * Registers an extra stat for the currently running benchmark.
     *
     * @param string $name
     * @param mixed  $value
     */
    public static function extraStat($name, $value)
    {
        self::$extraLines[] = [self::$currentBenchmark . '::' . $name, $value];
    }

    /**
     * Register a function to run before the benchmarks.
     */
    public static function setup(callable $hook)
    {
        self::$setupHooks[] = $hook;
    }

    /**
     * Register a function to run after the benchmarks.
     */
    public static function teardown(callable $hook)
    {
        self::$cleanupHooks[] = $hook;
    }

    /**
     * Extend default arguments with new ones.
     */
    public static function pushArgs($args)
    {
        self::$defaultArgs = array_merge(self::$defaultArgs, $args);
    }

    /**
     * Parse arguments from CLI or Query string,
     * then intersect with known default arg keys, and cast them to the original types.
     */
    private static function getArgs($expectedArgs)
    {
        $args = [];

        if (PHP_SAPI === 'cli') {
            $cleanedArgs = array_map(function ($arg) {
                return (strpos($arg, '--') !== 0) ? null : str_replace('--', '', $arg);
            }, $GLOBALS['argv'] ?? []);

            parse_str(implode('&', array_filter($cleanedArgs)), $args);
        } else {
            parse_str($_SERVER['QUERY_STRING'] ?? '', $args);
        }

        // Only keep keys that we actually expect
        $args = array_intersect_key($args, array_flip(array_keys($expectedArgs)));

        // Cast the type to the same as the default
        foreach ($expectedArgs as $key => $value) {
            if (isset($args[$key]) && $value !== null) {
                settype($args[$key], gettype($value));
            }
        }
        return $args;
    }

    /**
     * Runs a benchmark, returning timing or error info.
     *
     * @param callable $benchmark
     * @param float|int $multiplier
     *
     * @return array<string, mixed>
     */
    private static function runBenchmark($benchmark, $multiplier = 1)
    {
        self::startStopwatch();
        $r = null;
        try {
            $r = $benchmark($multiplier);
        } catch (\Exception $e) {
            $time = self::stopStopwatch();
            return [
                'error' => $e->getMessage(),
                'time'  => $time,
            ];
        }

        $time = self::stopStopwatch();

        // If returning INF is a signal to skip
        if ($r === INF) {
            return [
                'skipped' => true,
                'time'    => $time,
            ];
        }

        return [
            'result' => $r,
            'time'    => $time,
        ];
    }

    /**
     * Starts the stopwatch (resets $startTime).
     */
    private static function startStopwatch()
    {
        self::$startTime = self::time();
    }

    /**
     * Stops the stopwatch and adds elapsed time to totalTime.
     *
     * @return float Elapsed time for this benchmark run
     */
    private static function stopStopwatch()
    {
        $elapsed = self::time() - self::$startTime;
        self::$totalTime += $elapsed;
        return $elapsed;
    }

    /**
     * High-resolution or microtime fallback.
     *
     * @return float
     */
    private static function time()
    {
        return function_exists('hrtime')
            ? hrtime(true) / 1e9
            : microtime(true);
    }
}

// ---------------------------------------------------------------------
// Example usage:
//
// $results = PhpBench::bench();
// var_dump($results); // or print_r($results);
// ---------------------------------------------------------------------

