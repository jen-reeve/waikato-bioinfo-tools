/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryMap       } from 'plugin/nf-validation'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_hmmsearchmetagenome_pipeline'
include { HMMER_HMMSEARCH        } from '../modules/nf-core/hmmer/hmmsearch'
include { GUNZIP                 } from '../modules/nf-core/gunzip'
include { SEQKIT_GREP            } from '../modules/nf-core/seqkit/grep'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    DEFINE PROCESSES / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process seqidextract { // This pulls the sequence IDs from the table output from hmmsearch
    input:
    tuple val(meta), path(table)

    output:
    path "${meta.id}.txt", emit: table_clean

    script:
    """
    sed '/^#/ d' $table | awk '{print \$1}' > ${meta.id}.txt
    """

}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow HMMSEARCHMETAGENOME {

    take:
    samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()

    //
    // MODULE: Run HMMER_HMMSEARCH
    //

    ch_input = samplesheet.splitCsv(header: true)
        .map {
            row ->
            meta = [id:row.hmm_profile + "_" + file(row.metagenome).getSimpleName()]
            [meta, file("data/" + row.hmm_profile + ".hmm"), file("data/" + row.metagenome), true, true, true]
        }

    HMMER_HMMSEARCH (
        ch_input
    )

    ch_versions = ch_versions.mix(HMMER_HMMSEARCH.out.versions)

    //
    // MODULE: GUNZIP HMMSEARCH output
    //

    GUNZIP (
        HMMER_HMMSEARCH.out.target_summary
    )

    ch_versions = ch_versions.mix(GUNZIP.out.versions)

    //
    // Clean HMM output
    //
    ch_to_clean = GUNZIP.out.gunzip

    seqidextract(ch_to_clean)

    //
    // MODULE: SEQKIT_GREP to extract full length sequences from metagenome
    //

    ch_metagenome = samplesheet.splitCsv(header: true)
        .map {
            row ->
            meta = [id:row.hmm_profile + "_" + file(row.metagenome).getSimpleName()]
            [meta, file("data/" + row.metagenome)]
        }

    ch_seqs = seqidextract.out.table_clean

    SEQKIT_GREP (
        ch_metagenome,
        ch_seqs
    )

    ch_versions = ch_versions.mix(SEQKIT_GREP.out.versions)

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_pipeline_software_mqc_versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    emit:
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
