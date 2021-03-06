<?php

namespace App\Repository;

use Doctrine\ODM\MongoDB\Repository\DocumentRepository;

/**
 * AboutRepository.
 *
 * This class was generated by the Doctrine ORM. Add your own custom
 * repository methods below.
 */
class ConfigurationRepository extends DocumentRepository
{
    public function findConfiguration()
    {
        $qb = $this->query('Configuration');

        return $qb->getQuery()->getSingleResult();
    }
}
