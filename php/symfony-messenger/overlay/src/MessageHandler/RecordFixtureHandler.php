<?php

namespace App\MessageHandler;

use App\Message\RecordFixture;
use Doctrine\DBAL\Connection;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final readonly class RecordFixtureHandler
{
    public function __construct(private Connection $database)
    {
    }

    public function __invoke(RecordFixture $message): void
    {
        $this->database->insert('suite_results', ['value' => $message->value]);
    }
}
