import groovy.json.JsonOutput

/**
 * Small collection of static helpers used across the pipeline.
 *
 * Classes placed in lib/ are added to the Nextflow classpath automatically,
 * so these methods can be called from main.nf / nextflow.config without an
 * explicit import (e.g. `Utils.reportRunStatus(...)`).
 */
class Utils {

    /**
     * Parse a Nextflow CLI param into a strict boolean.
     *
     * Accepts:
     *  - Boolean: true/false
     *  - Number: 1/0
     *  - String (case-insensitive, trimmed): "true"/"false"/"1"/"0"
     *
     * If value is null (or empty string), returns defaultValue.
     * Otherwise throws IllegalArgumentException on invalid inputs.
     */
    static boolean parseCLIBool(Object givenValue, boolean defaultValue = false, String paramName = null) {
        if (givenValue == null) {
            return defaultValue
        }

        if (givenValue instanceof Boolean) {
            return (Boolean) givenValue
        }

        if (givenValue instanceof Number) {
            int n = ((Number) givenValue).intValue()
            if (n == 0) return false
            if (n == 1) return true
            throw new IllegalArgumentException(errMsg(paramName, givenValue, "expected 0 or 1"))
        }

        String s = givenValue.toString().trim()
        if (s.length() == 0) {
            throw new IllegalArgumentException(errMsg(paramName, givenValue, "empty string is not a valid, expected true/false/1/0"))
        }

        s = s.toLowerCase()
        if (s == "true" || s == "1")  return true
        if (s == "false" || s == "0") return false

        throw new IllegalArgumentException(errMsg(paramName, givenValue, "expected true/false/1/0 (case-insensitive)"))
    }

    // ---- Run-status reporting helpers ----

    /**
     * Build a run-status payload from the Nextflow `workflow` metadata and
     * POST it to the status API. `status` is one of: running, succeeded, failed.
     *
     * Fields that are not yet known at the call site (e.g. duration/success
     * when reporting "running") are serialised as null. Returns true on a 2xx
     * response; any failure is caught and reported as false so that status
     * reporting can never change the pipeline's own exit status.
     */
    static boolean reportRunStatus(String url, String status, workflow, params) {
        if (!url) {
            return false
        }
        Map payload = [
            status       : status,
            run_name     : workflow.runName,
            session_id   : workflow.sessionId?.toString(),
            study_id     : params?.study_id,
            pipeline     : workflow.manifest?.name,
            version      : workflow.manifest?.version,
            revision     : workflow.revision,
            commit_id    : workflow.commitId,
            start_time   : workflow.start?.toString(),
            complete_time: workflow.complete?.toString(),
            duration     : workflow.duration?.toString(),
            exit_status  : workflow.exitStatus,
            success      : workflow.success,
            error_message: workflow.errorMessage,
        ]
        return postJson(url, payload)
    }

    // ---- private helpers ----

    private static String errMsg(String paramName, Object givenValue, String expectation) {
        String namePart = paramName ? "--${paramName} " : ""
        return "Invalid ${namePart}${givenValue} (${expectation})"
    }

    /**
     * POST a JSON-serialised payload to `url`.
     *
     * Network errors and non-2xx responses are caught and logged to stderr
     * so that a reporting failure never causes the pipeline itself to fail.
     *
     * @return true if the endpoint accepted the payload (HTTP 2xx), false otherwise
     */
    private static boolean postJson(String url, Map payload, int timeoutMs = 10_000) {
        if (!url || payload == null) {
            return false
        }

        HttpURLConnection conn = null
        try {
            String body = JsonOutput.toJson(payload)
            conn = (HttpURLConnection) new URL(url).openConnection()
            conn.setRequestMethod('POST')
            conn.setRequestProperty('Content-Type', 'application/json; charset=UTF-8')
            conn.setRequestProperty('Accept', 'application/json')
            conn.setConnectTimeout(timeoutMs)
            conn.setReadTimeout(timeoutMs)
            conn.setDoOutput(true)

            conn.outputStream.withWriter('UTF-8') { writer ->
                writer.write(body)
            }

            int code = conn.getResponseCode()
            if (code >= 200 && code < 300) {
                return true
            }
            System.err.println("WARNING: status API returned HTTP ${code}")
            return false
        } catch (SocketTimeoutException e) {
            System.err.println("WARNING: status API request timed out after ${timeoutMs}ms: ${e.message}")
            return false
        } catch (Exception e) {
            System.err.println("WARNING: status API request failed: ${e.message}")
            return false
        } finally {
            if (conn != null) {
                conn.disconnect()
            }
        }
    }
}
