"""Module #5 (Chain of Custody & Reporting) Integration Interface.

Represents the reporting and audit layer responsible for verifying evidence
integrity, compiling court-ready forensic timelines, and rendering PDF/HTML
case reports with Section 65B Indian Evidence Act / BSA certificates.
"""

from abc import ABC, abstractmethod
from typing import Any

from src.timeline.schemas import TimelineExportResponse


class ReportingEngineInterface(ABC):
    """Integration contract that Module #5 (Reporting Engine) will fulfill."""

    @abstractmethod
    async def build_court_report(self, export: TimelineExportResponse) -> dict[str, Any]:
        """Compile verified timeline, source provenance, and audit trail into forensic report."""
        pass


class MockReportingEngine(ReportingEngineInterface):
    """Mock adapter demonstrating Module #5 consumption of Module #3 exports."""

    async def build_court_report(self, export: TimelineExportResponse) -> dict[str, Any]:
        """Validate export package and return simulated forensic report summary."""
        verified_events = 0
        unverified_events = 0

        for ev in export.events:
            if ev.raw_timestamp and ev.utc_timestamp:
                verified_events += 1
            else:
                unverified_events += 1

        return {
            "case_id": export.case_id,
            "report_title": f"Forensic Surveillance Timeline Report — Case {export.case_id}",
            "generated_at_utc": export.export_generated_at_utc.isoformat(),
            "forensic_integrity_status": "VERIFIED_BITSTREAM_INTACT",
            "section_65b_certificate_ready": True,
            "total_timeline_events": export.total_events,
            "verified_events_count": verified_events,
            "unverified_events_count": unverified_events,
            "cross_camera_correlations_count": export.total_correlations,
            "clock_calibrations_count": export.total_corrections,
            "integrity_statement": export.integrity_statement,
        }
