<?php

namespace App\Controller;

use App\Message\RecordFixture;
use Doctrine\DBAL\Connection;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Routing\Attribute\Route;

final readonly class FixtureController
{
    public function __construct(private Connection $database)
    {
    }

    #[Route('/suite/dispatch', methods: ['POST'])]
    public function dispatch(Request $request, MessageBusInterface $bus): JsonResponse
    {
        $value = $request->request->getString('value');
        if (! preg_match('/^fixture-[0-9]+$/D', $value)) {
            return new JsonResponse(['error' => 'invalid value'], 400);
        }
        $this->database->executeStatement('CREATE TABLE IF NOT EXISTS suite_results (value TEXT PRIMARY KEY)');
        $bus->dispatch(new RecordFixture($value));

        return new JsonResponse(['queued' => true], 202);
    }

    #[Route('/suite/results', methods: ['GET'])]
    public function results(): JsonResponse
    {
        return new JsonResponse([
            'pending' => (int) $this->database->fetchOne('SELECT COUNT(*) FROM messenger_messages'),
            'handled' => $this->database->fetchFirstColumn('SELECT value FROM suite_results ORDER BY value'),
        ]);
    }
}
