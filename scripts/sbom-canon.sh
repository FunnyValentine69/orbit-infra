#!/usr/bin/env bash
set -euo pipefail

jq -cS '
  def canonical_package:
    {
      name,
      versionInfo,
      checksums: ((.checksums // [])
        | map({algorithm, checksumValue})
        | sort_by([.algorithm, .checksumValue])),
      licenseConcluded,
      licenseDeclared,
      externalRefs: ((.externalRefs // [])
        | map({referenceCategory, referenceType, referenceLocator})
        | sort_by([.referenceCategory, .referenceType, .referenceLocator]))
    };

  (.packages // []) as $source_packages
  | ($source_packages
      | map(.SPDXID as $id | {key: $id, value: (canonical_package | tojson)})
      | from_entries) as $package_identities
  | (.SPDXID // "SPDXRef-DOCUMENT") as $document_id
  | def canonical_endpoint:
      if . == "SPDXRef-DOCUMENT" or . == $document_id then
        "DOCUMENT"
      elif $package_identities[.] != null then
        $package_identities[.]
      else
        .
      end;
  {
    packages: ($source_packages
      | map(canonical_package)
      | sort_by(tojson)),
    relationships: ((.relationships // [])
      | map({
          spdxElementId: (.spdxElementId | canonical_endpoint),
          relationshipType,
          relatedSpdxElement: (.relatedSpdxElement | canonical_endpoint)
        })
      | sort_by([.spdxElementId, .relationshipType, .relatedSpdxElement]))
  }
'
