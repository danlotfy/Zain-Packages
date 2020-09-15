  CREATE OR REPLACE PACKAGE APPS.XX_PO_INT_ADI_PKG 
is

/* $Header: XX_PO_INT_ADI_PKG_2020_09_13.sql 2020.09.13 20/09/13 14:00:00 ahmed noship $ */

  function import_pr_line(
    p_org_id                      number,
    p_batch_id                    number,
    p_interface_source_code       varchar2,
    p_source_type_code            varchar2,
    p_currency_code               varchar2,
    p_rate_type                   varchar2,
    p_rate_date                   date,
    p_rate                        number,
    --p_interface_source_line_id    number,
    p_line_num                    number, 
    p_item_code                   varchar2,
    p_unit_of_measure             varchar2,
    p_currency_unit_price         number,
    p_requestor_number            varchar2,
    p_destination_organization_id number,
    p_deliver_to_location_id      number,
    p_need_by_date                date,
    p_suggested_vendor_num        varchar2,
    p_suggested_vendor_site_code  varchar2,
    p_note_to_buyer               varchar2,
    p_line_attribute_category     varchar2,
    p_line_attribute1             varchar2,
    p_line_attribute2             varchar2,
    p_line_attribute3             varchar2,
    p_line_attribute4             varchar2,
    p_line_attribute5             varchar2,
    p_line_attribute6             varchar2,
    p_line_attribute7             varchar2,
    p_line_attribute8             varchar2,
    p_line_attribute9             varchar2,
    p_line_attribute10            varchar2,
    p_line_attribute11            varchar2,
    p_line_attribute12            varchar2,
    p_line_attribute13            varchar2,
    p_line_attribute14            varchar2,
    p_line_attribute15            varchar2,
    p_allocation_type             varchar2,
    p_allocation_value            number,
    p_charge_account_id           number,
    p_dist_quantity               number,
    p_expenditure_type            varchar2,
    p_expenditure_item_date       date,
    p_gl_date                     date,
    p_project_num                 varchar2,
    p_task_num                    varchar2,
    p_distribution_attribute10    varchar2)
  return varchar2;
    

end;

/

CREATE OR REPLACE PACKAGE BODY APPS.XX_PO_INT_ADI_PKG 
is

   FUNCTION import_pr_line (p_org_id                         NUMBER,
                            p_batch_id                       NUMBER,
                            p_interface_source_code          VARCHAR2,
                            p_source_type_code               VARCHAR2,
                            p_currency_code                  VARCHAR2,
                            p_rate_type                      VARCHAR2,
                            p_rate_date                      DATE,
                            p_rate                           NUMBER,
--                            p_interface_source_line_id       NUMBER,
                            p_line_num                       NUMBER,
                            p_item_code                      VARCHAR2,
                            p_unit_of_measure                VARCHAR2,
                            p_currency_unit_price            NUMBER,
                            p_requestor_number               VARCHAR2,
                            p_destination_organization_id    NUMBER,
                            p_deliver_to_location_id         NUMBER,
                            p_need_by_date                   DATE,
                            p_suggested_vendor_num           VARCHAR2,
                            p_suggested_vendor_site_code     VARCHAR2,
                            p_note_to_buyer                  VARCHAR2,
                            p_line_attribute_category        VARCHAR2,
                            p_line_attribute1                VARCHAR2,
                            p_line_attribute2                VARCHAR2,
                            p_line_attribute3                VARCHAR2,
                            p_line_attribute4                VARCHAR2,
                            p_line_attribute5                VARCHAR2,
                            p_line_attribute6                VARCHAR2,
                            p_line_attribute7                VARCHAR2,
                            p_line_attribute8                VARCHAR2,
                            p_line_attribute9                VARCHAR2,
                            p_line_attribute10               VARCHAR2,
                            p_line_attribute11               VARCHAR2,
                            p_line_attribute12               VARCHAR2,
                            p_line_attribute13               VARCHAR2,
                            p_line_attribute14               VARCHAR2,
                            p_line_attribute15               VARCHAR2,
                            p_allocation_type                VARCHAR2,
                            p_allocation_value               NUMBER,
                            p_charge_account_id              NUMBER,
                            p_dist_quantity                  NUMBER,
                            p_expenditure_type               VARCHAR2,
                            p_expenditure_item_date          DATE,
                            p_gl_date                        DATE,
                            p_project_num                    VARCHAR2,
                            p_task_num                       VARCHAR2,
                            p_distribution_attribute10       VARCHAR2)
      RETURN VARCHAR2
   IS
      lError       VARCHAR2 (32676);
      lLine        po_requisitions_interface_all%ROWTYPE;
      lDist        po_req_dist_interface_all%ROWTYPE;
      lCapex       BOOLEAN;
      lfunc_curr   VARCHAR2 (15);

      CURSOR lk (x_lookup_type VARCHAR2, x_lookup_code VARCHAR2)
      IS
         SELECT tag
           FROM fnd_lookup_values
          WHERE lookup_type = x_lookup_type AND lookup_code = x_lookup_code;

      CURSOR itm (
         x_organization_id    NUMBER,
         x_item_code          VARCHAR2)
      IS
         SELECT inventory_item_id,
                item_type,
                (SELECT cat.category_id
                   FROM mtl_item_categories_v cat
                  WHERE     cat.inventory_item_id = mtl.inventory_item_id
                        AND cat.organization_id = mtl.organization_id
                        AND cat.structure_id = 201)
                   category_id                        -- Purchasing Categories
           FROM mtl_system_items_kfv mtl
          WHERE     organization_id = x_organization_id
                AND concatenated_segments = x_item_code;

      CURSOR par (x_organization_id NUMBER)
      IS
         SELECT ap_accrual_account
           FROM mtl_parameters
          WHERE organization_id = x_organization_id;

      CURSOR req (
         x_org_id             NUMBER,
         x_employee_number    VARCHAR2)
      IS
         SELECT person_id, current_employee_flag
           FROM per_all_people_f per, hr_operating_units org
          WHERE     1 = 1
                AND per.business_group_id = org.business_group_Id
                AND per.employee_number = x_employee_number
                AND TRUNC (SYSDATE) BETWEEN per.effective_start_date
                                        AND per.effective_end_date
                AND org.organization_id = x_org_id;

      CURSOR vnd
      IS
         SELECT sup.vendor_id, sit.vendor_site_id
           FROM ap_suppliers sup, ap_supplier_sites_all sit
          WHERE     sup.vendor_id = sit.vendor_id(+)
                AND sup.segment1 = p_suggested_vendor_num
                AND sit.vendor_site_code(+) = p_suggested_vendor_site_code
                AND sit.org_id(+) = p_org_id;

      PROCEDURE append_error (x_message VARCHAR2)
      IS
      BEGIN
         IF lError IS NOT NULL
         THEN
            lError := lError || CHR (10);
         END IF;

         lError := lError || x_message;
      END;
   BEGIN
      SAVEPOINT xx_po_int_adi_imp_pr_lin_sp1;

      BEGIN
         SELECT *
           INTO lLine
           FROM po_requisitions_interface_all
          WHERE     org_id = p_org_id
                AND batch_id = p_batch_id
                AND line_num = p_line_num;
--                AND interface_source_line_id = p_interface_source_line_id;
      EXCEPTION
         WHEN NO_DATA_FOUND
         THEN
            NULL;
      END;

      -- new line
      IF lLine.batch_id IS NULL
      THEN
         lLine.batch_id := p_batch_id;
         lLine.group_code := TO_CHAR (p_batch_id);
         lLine.interface_source_code := p_interface_source_code;
         lLine.interface_source_line_id := to_number(p_batch_id||'00'||p_line_num);
         lLine.line_num := p_line_num;
         lLine.source_type_code := p_source_type_code;

         FOR i IN lk ('XX_PR_UPLOAD_DEST_TYPE', lLine.interface_source_code)
         LOOP
            lLine.destination_type_code := i.tag;
         END LOOP;

         IF lLine.destination_type_code IS NULL
         THEN
            append_error (
                  'Unable to retrieve DESTINATION_TYPE_CODE from INTERFACE_SOURCE_CODE = "'
               || lLine.interface_source_code
               || '"');
         END IF;

         lLine.quantity := 0;          --  will be updated based on p_quantity
         --lLine.unit_price                  := p_unit_price                ;
         lLine.authorization_status := 'INCOMPLETE';
         lLine.preparer_id := fnd_global.employee_id;
         lLine.created_by := fnd_global.employee_id;
         lLine.creation_date := SYSDATE;
         lLine.last_updated_by := fnd_global.employee_id;
         lLine.last_update_date := SYSDATE;
         lCapex := FALSE;

         FOR i IN itm (p_destination_organization_id, p_item_code)
         LOOP
            lLine.item_id := i.inventory_item_id;
            lLine.category_id := i.category_id;

            IF i.item_type = 'CAPEX ITEM'
            THEN
               lCapex := TRUE;
            END IF;
         END LOOP;

         IF lLine.item_id IS NULL
         THEN
            append_error (
               'Unable to retrieve inventory item "' || p_item_code || '"');
         ELSIF lLine.category_id IS NULL
         THEN
            append_error (
                  'Unable to retrieve "Purchasing Categories" from inventory item "'
               || p_item_code
               || '"');
         END IF;

         FOR i IN par (p_destination_organization_id)
         LOOP
            lLine.accrual_account_id := i.ap_accrual_account;
         END LOOP;

         IF lLine.accrual_account_id IS NULL
         THEN
            append_error (
               'Unable to retrieve AP Accrual Account from destination organization');
         END IF;

         lLine.unit_of_measure := p_unit_of_measure;
         lLine.destination_organization_id := p_destination_organization_id;

         FOR i IN req (p_org_id, p_requestor_number)
         LOOP
            IF i.current_employee_flag = 'Y'
            THEN
               lLine.deliver_to_requestor_id := i.person_id;
            ELSE
               append_error (
                  'Employee "' || p_requestor_number || '" is not active');
            END IF;
         END LOOP;

         IF lLine.deliver_to_requestor_id IS NULL
         THEN
            append_error ('Invalid Employee Number "' || p_item_code || '"');
         END IF;

         lLine.deliver_to_location_id := p_deliver_to_location_id;
         lLine.need_by_date := p_need_by_date;
         lLine.currency_code := p_currency_code;
         
                  IF lCapex
         THEN
            lLine.project_accounting_context := 'Y';                      

         ELSE
            lLine.project_accounting_context := 'N';
         END IF;

         BEGIN
            SELECT CURRENCY_CODE
              INTO lfunc_curr
              FROM gl_ledgers
             WHERE ledger_id = fnd_profile.VALUE ('GL_SET_OF_BKS_ID');

            IF lfunc_curr = p_currency_code
            THEN
               lLine.unit_price := p_currency_unit_price;
            ELSE
               lLine.currency_unit_price := p_currency_unit_price;
            END IF;
         EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
               append_error (
                     'Unable to retrieve Local Currency Code from Profile: '
                  || fnd_profile.VALUE ('GL_SET_OF_BKS_ID'));
         END;

         lLine.rate := p_rate;
         lLine.rate_date := p_rate_date;
         lLine.rate_type := p_rate_type;
         lLine.org_id := p_org_id;
         lLine.multi_distributions := 'Y';

         SELECT po_requisitions_interface_s.NEXTVAL
           INTO lLine.req_dist_sequence_id
           FROM DUAL;

         lLine.line_attribute_category := p_line_attribute_category;
         lLine.line_attribute1 := p_line_attribute1;
         lLine.line_attribute2 := p_line_attribute2;
         lLine.line_attribute3 := p_line_attribute3;
         lLine.line_attribute4 := p_line_attribute4;
         lLine.line_attribute5 := p_line_attribute5;
         lLine.line_attribute6 := p_line_attribute6;
         lLine.line_attribute7 := p_line_attribute7;
         lLine.line_attribute8 := p_line_attribute8;
         lLine.line_attribute9 := p_line_attribute9;
         lLine.line_attribute10 := p_line_attribute10;
         lLine.line_attribute11 := p_line_attribute11;
         lLine.line_attribute12 := p_line_attribute12;
         lLine.line_attribute13 := p_line_attribute13;
         lLine.line_attribute14 := p_line_attribute14;
         lLine.line_attribute15 := p_line_attribute15;

         IF p_suggested_vendor_num IS NOT NULL
         THEN
            FOR i IN vnd
            LOOP
               lLine.suggested_vendor_id := i.vendor_id;
               lLine.suggested_vendor_site_id := i.vendor_site_id;
            END LOOP;

            IF     lLine.suggested_vendor_id IS NULL
               AND p_suggested_vendor_num IS NOT NULL
            THEN
               append_error (
                  'Invalid Vendor Number "' || p_suggested_vendor_num || '"');
            END IF;

            IF     lLine.suggested_vendor_site_id IS NULL
               AND p_suggested_vendor_site_code IS NOT NULL
            THEN
               append_error (
                     'Invalid Vendor Site "'
                  || p_suggested_vendor_site_code
                  || '"');
            END IF;
         END IF;

         lLine.note_to_buyer := p_note_to_buyer;

         IF lError IS NULL
         THEN
            INSERT
              INTO po_requisitions_interface_all (batch_id,
                                                  group_code,
                                                  project_accounting_context,
                                                  interface_source_code,
                                                  interface_source_line_id,
                                                  line_num,
                                                  source_type_code,
                                                  destination_type_code,
                                                  quantity,
                                                  unit_price,
                                                  authorization_status,
                                                  preparer_id,
                                                  created_by,
                                                  creation_date,
                                                  last_updated_by,
                                                  last_update_date,
                                                  item_id,
                                                  category_id,
                                                  unit_of_measure,
                                                  destination_organization_id,
                                                  deliver_to_requestor_id,
                                                  deliver_to_location_id,
                                                  need_by_date,
                                                  currency_code,
                                                  currency_unit_price,
                                                  rate,
                                                  rate_date,
                                                  rate_type,
                                                  org_id,
                                                  multi_distributions,
                                                  req_dist_sequence_id,
                                                  line_attribute_category,
                                                  line_attribute1,
                                                  line_attribute2,
                                                  line_attribute3,
                                                  line_attribute4,
                                                  line_attribute5,
                                                  line_attribute6,
                                                  line_attribute7,
                                                  line_attribute8,
                                                  line_attribute9,
                                                  line_attribute10,
                                                  line_attribute11,
                                                  line_attribute12,
                                                  line_attribute13,
                                                  line_attribute14,
                                                  line_attribute15,
                                                  suggested_vendor_id,
                                                  suggested_vendor_site_id,
                                                  note_to_buyer)
            VALUES (lLine.batch_id,
                    lLine.group_code,
                    lLine.project_accounting_context,
                    lLine.interface_source_code,
                    lLine.interface_source_line_id,
                    lLine.line_num,
                    lLine.source_type_code,
                    lLine.destination_type_code,
                    lLine.quantity,
                    lLine.unit_price,
                    lLine.authorization_status,
                    lLine.preparer_id,
                    lLine.created_by,
                    lLine.creation_date,
                    lLine.last_updated_by,
                    lLine.last_update_date,
                    lLine.item_id,
                    lLine.category_id,
                    lLine.unit_of_measure,
                    lLine.destination_organization_id,
                    lLine.deliver_to_requestor_id,
                    lLine.deliver_to_location_id,
                    lLine.need_by_date,
                    lLine.currency_code,
                    lLine.currency_unit_price,
                    lLine.rate,
                    lLine.rate_date,
                    lLine.rate_type,
                    lLine.org_id,
                    lLine.multi_distributions,
                    lLine.req_dist_sequence_id,
                    lLine.line_attribute_category,
                    lLine.line_attribute1,
                    lLine.line_attribute2,
                    lLine.line_attribute3,
                    lLine.line_attribute4,
                    lLine.line_attribute5,
                    lLine.line_attribute6,
                    lLine.line_attribute7,
                    lLine.line_attribute8,
                    lLine.line_attribute9,
                    lLine.line_attribute10,
                    lLine.line_attribute11,
                    lLine.line_attribute12,
                    lLine.line_attribute13,
                    lLine.line_attribute14,
                    lLine.line_attribute15,
                    lLine.suggested_vendor_id,
                    lLine.suggested_vendor_site_id,
                    lLine.note_to_buyer);
         END IF;
      END IF;

      IF lError IS NULL
      THEN
         lDist.batch_id := lLine.batch_id;
         lDist.interface_source_code := lLine.interface_source_code;
         lDist.interface_source_line_id := lLine.interface_source_line_id;
         lDist.dist_sequence_id := lLine.req_dist_sequence_id;
         lDist.org_id := lLine.org_id;
         lDist.accrual_account_id := lLine.accrual_account_id;
         lDist.allocation_type := p_allocation_type;
         lDist.allocation_value := p_allocation_value;
         lDist.budget_account_id := p_charge_account_id;
         lDist.charge_account_id := p_charge_account_id;
         lDist.destination_organization_id :=
            lLine.destination_organization_id;
         lDist.destination_type_code := lLine.destination_type_code;

         SELECT NVL (MAX (distribution_number), 0) + 1
           INTO lDist.distribution_number
           FROM po_req_dist_interface_all
          WHERE     org_id = lLine.org_id
                AND batch_id = lLine.batch_id
                AND interface_source_line_id = lLine.interface_source_line_id;


         lDist.gl_date := p_gl_date;
         lDist.group_code := lLine.group_code;

         IF lCapex
         THEN
            lDist.project_accounting_context := 'Y'; 
            lDist.expenditure_type := p_expenditure_type;
            lDist.expenditure_item_date := p_expenditure_item_date;
            lDist.expenditure_organization_id := lLine.org_id; 
            lDist.project_num := p_project_num;
            lDist.task_num := p_task_num;

            IF lDist.project_num IS NULL
            THEN
               append_error ('Project Number is missing for CAPEX item');
            END IF;

            IF lDist.task_num IS NULL
            THEN
               append_error ('Project Task Number is missing for CAPEX item');
            END IF;
         ELSE
            lDist.project_accounting_context := 'N';
         END IF;

         lDist.quantity := p_dist_quantity;
         lDist.variance_account_id := p_charge_account_id;
         lDist.distribution_attribute10 := p_distribution_attribute10;

         INSERT INTO po_req_dist_interface_all (batch_id,
                                                interface_source_code,
                                                interface_source_line_id,
                                                dist_sequence_id,
                                                org_id,
                                                accrual_account_id,
                                                allocation_type,
                                                allocation_value,
                                                budget_account_id,
                                                charge_account_id,
                                                destination_organization_id,
                                                destination_type_code,
                                                distribution_number,
                                                expenditure_type,
                                                expenditure_item_date,
                                                expenditure_organization_id,
                                                gl_date,
                                                group_code,
                                                project_accounting_context,
                                                project_num,
                                                task_num,
                                                quantity,
                                                variance_account_id,
                                                distribution_attribute10)
              VALUES (lDist.batch_id,
                      lDist.interface_source_code,
                      lDist.interface_source_line_id,
                      lDist.dist_sequence_id,
                      lDist.org_id,
                      lDist.accrual_account_id,
                      lDist.allocation_type,
                      lDist.allocation_value,
                      lDist.budget_account_id,
                      lDist.charge_account_id,
                      lDist.destination_organization_id,
                      lDist.destination_type_code,
                      lDist.distribution_number,
                      lDist.expenditure_type,
                      lDist.expenditure_item_date,
                      lDist.expenditure_organization_id,
                      lDist.gl_date,
                      lDist.group_code,
                      lDist.project_accounting_context,
                      lDist.project_num,
                      lDist.task_num,
                      lDist.quantity,
                      lDist.variance_account_id,
                      lDist.distribution_attribute10);

         SELECT NVL (SUM (quantity), 0)
           INTO lLine.quantity
           FROM po_req_dist_interface_all
          WHERE     org_id = lLine.org_id
                AND batch_id = lLine.batch_id
                AND interface_source_line_id = lLine.interface_source_line_id;

         UPDATE po_requisitions_interface_all
            SET quantity = lLine.quantity
          WHERE     org_id = lLine.org_id
                AND batch_id = lLine.batch_id
                AND interface_source_line_id = lLine.interface_source_line_id;
      END IF;

      IF lError IS NOT NULL
      THEN
         ROLLBACK TO xx_po_int_adi_imp_pr_lin_sp1;
      END IF;

      RETURN (lError);
   EXCEPTION
      WHEN OTHERS
      THEN
         lError :=
               DBMS_UTILITY.format_error_stack
            || DBMS_UTILITY.format_error_backtrace;
         ROLLBACK TO xx_po_int_adi_imp_pr_lin_sp1;
         RETURN (lError);
   END;
END;

/
